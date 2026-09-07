using System.Text;
using System.Security.Claims;
using System.Threading.RateLimiting;
using FluentValidation;
using FluentValidation.AspNetCore;
using Hangfire;
using Hangfire.SqlServer;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.HttpOverrides;
using Microsoft.AspNetCore.OpenApi;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using Scalar.AspNetCore;
using Serilog;
using StackExchange.Redis;
using ConcertTicketing.API;
using ConcertTicketing.API.Middleware;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Application.Services;
using ConcertTicketing.Application.Validators;
using ConcertTicketing.Infrastructure.BackgroundJobs;
using ConcertTicketing.Infrastructure.Cache;
using ConcertTicketing.Infrastructure.Data;
using ConcertTicketing.Infrastructure.Repositories;

// ── Bootstrap Serilog sớm để bắt lỗi khởi động ────────────────────────────
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    // ── Cấu hình cục bộ chứa bí mật ──────────────────────────────────────────
    // appsettings.json trong repository KHÔNG chứa bí mật nào. Giá trị thật đến từ
    // appsettings.Local.json (dev/demo, nằm trong .gitignore) hoặc biến môi trường
    // (môi trường thật).
    //
    // THỨ TỰ ƯU TIÊN: biến môi trường LUÔN thắng file.
    // WebApplication.CreateBuilder đã nạp biến môi trường TRƯỚC dòng này, nên nếu chỉ
    // thêm file JSON thì file sẽ ghi đè biến môi trường — ngược hoàn toàn với quy ước.
    // Hậu quả thực tế: triển khai bằng biến môi trường nhưng máy còn sót một
    // appsettings.Local.json cũ thì hệ thống lặng lẽ dùng chuỗi kết nối và bí mật cũ.
    // Vì vậy nạp lại biến môi trường SAU file để khôi phục đúng thứ tự.
    builder.Configuration.AddJsonFile("appsettings.Local.json", optional: true, reloadOnChange: false);
    builder.Configuration.AddEnvironmentVariables();
    builder.Configuration.AddEnvironmentVariables(prefix: "CONCERT_");

    // ── Serilog ───────────────────────────────────────────────────────────────
    builder.Host.UseSerilog((ctx, services, config) =>
        config.ReadFrom.Configuration(ctx.Configuration)
              .ReadFrom.Services(services));

    // ── Kiểm tra cấu hình bắt buộc — DỪNG NGAY LÚC KHỞI ĐỘNG ────────────────
    // Trước đây chỉ Jwt:Secret và PaymentSignature:Secret được kiểm; những khóa còn lại
    // dùng toán tử `!` nên nếu thiếu thì lỗi chỉ nổ ra lúc có request thật: thiếu
    // Jwt:AccessTokenExpiryMinutes làm MỌI lần đăng nhập trả HTTP 500 mà không nói được
    // nguyên nhân. Sai cấu hình phải làm tiến trình không khởi động được, không phải làm
    // hệ thống chạy rồi hỏng lẻ tẻ.
    static string RequireConfig(WebApplicationBuilder b, string key, int minLength = 1)
    {
        var value = b.Configuration[key];
        if (string.IsNullOrWhiteSpace(value))
            throw new InvalidOperationException($"Thiếu cấu hình bắt buộc: '{key}'.");
        if (value.Length < minLength)
            throw new InvalidOperationException(
                $"Cấu hình '{key}' phải có độ dài tối thiểu {minLength} ký tự.");
        return value;
    }

    static int RequireIntConfig(WebApplicationBuilder b, string key, int min)
    {
        var raw = RequireConfig(b, key);
        if (!int.TryParse(raw, out var value) || value < min)
            throw new InvalidOperationException(
                $"Cấu hình '{key}' phải là số nguyên >= {min} (hiện tại: '{raw}').");
        return value;
    }

    var connectionString = builder.Configuration.GetConnectionString("Default");
    if (string.IsNullOrWhiteSpace(connectionString))
        throw new InvalidOperationException("Thiếu cấu hình bắt buộc: 'ConnectionStrings:Default'.");

    // ── CORS ─────────────────────────────────────────────────────────────────
    // Origin lấy từ cấu hình thay vì viết cứng localhost:5173 — nếu không, frontend
    // triển khai ở bất kỳ địa chỉ nào khác đều bị trình duyệt chặn hoàn toàn.
    var allowedOrigins = builder.Configuration
        .GetSection("Cors:AllowedOrigins").Get<string[]>() ?? Array.Empty<string>();

    if (allowedOrigins.Length == 0)
        throw new InvalidOperationException(
            "Thiếu cấu hình bắt buộc: 'Cors:AllowedOrigins' (danh sách origin của frontend).");

    builder.Services.AddCors(options =>
    {
        options.AddPolicy("AllowFrontend", policy =>
        {
            policy.WithOrigins(allowedOrigins)
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials(); // Bắt buộc để gửi/nhận HttpOnly Cookie (Refresh Token)
        });
    });

    // ── Controllers + FluentValidation ────────────────────────────────────────
    builder.Services.AddControllers();
    builder.Services.AddFluentValidationAutoValidation();
    builder.Services.AddValidatorsFromAssemblyContaining<CreateBookingValidator>();

    // ── OpenAPI / Scalar ──────────────────────────────────────────────
    // Thêm Bearer security scheme → Scalar UI sẽ hiển thị nút "Authorize"
    // để nhập JWT token test các endpoint cần xác thực.
    builder.Services.AddOpenApi(options =>
    {
        options.AddDocumentTransformer((document, context, ct) =>
        {
            document.Components ??= new OpenApiComponents();
            document.Components.SecuritySchemes = new Dictionary<string, OpenApiSecurityScheme>
            {
                ["Bearer"] = new OpenApiSecurityScheme
                {
                    Type        = SecuritySchemeType.Http,
                    Scheme      = "bearer",
                    BearerFormat = "JWT",
                    Description = "Nhập Access Token (không cần prefix 'Bearer ')."
                }
            };
            return Task.CompletedTask;
        });
    });

    // ── JWT Authentication ────────────────────────────────────────────────────
    // Secret >= 32 ký tự = 256-bit, tương xứng với HMAC-SHA256.
    var jwtSecret   = RequireConfig(builder, "Jwt:Secret", minLength: 32);
    var jwtIssuer   = RequireConfig(builder, "Jwt:Issuer");
    var jwtAudience = RequireConfig(builder, "Jwt:Audience");

    // AuthService đọc lại hai khóa này bằng int.Parse ở mỗi lần cấp token; kiểm tại đây
    // để lỗi cấu hình lộ ra lúc khởi động thay vì lúc người dùng đăng nhập.
    _ = RequireIntConfig(builder, "Jwt:AccessTokenExpiryMinutes", min: 1);
    _ = RequireIntConfig(builder, "Jwt:RefreshTokenExpiryDays",  min: 1);

    builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
        .AddJwtBearer(options =>
        {
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer           = true,
                ValidateAudience         = true,
                ValidateLifetime         = true,
                ValidateIssuerSigningKey = true,
                ValidIssuer              = jwtIssuer,
                ValidAudience            = jwtAudience,
                IssuerSigningKey         = new SymmetricSecurityKey(
                                               Encoding.UTF8.GetBytes(jwtSecret)),
                ClockSkew                = TimeSpan.Zero  // Không cho phép skew
            };
        });

    builder.Services.AddAuthorization();

    // ── Rate Limiting (built-in ASP.NET Core 9) ───────────────────────────────
    // QUAN TRỌNG: UseRateLimiter() phải đặt SAU UseAuthentication() trong pipeline
    // để UserID-based limiter có thể đọc JWT Claims đã giải mã.
    builder.Services.AddRateLimiter(options =>
    {
        // Booking: 2 req/10s per UserID — chống double-click
        options.AddPolicy("booking", httpContext =>
            RateLimitPartition.GetSlidingWindowLimiter(
                partitionKey: GetClientPartitionKey(httpContext, useUserId: true),
                factory: _ => new SlidingWindowRateLimiterOptions
                {
                    Window               = TimeSpan.FromSeconds(10),
                    PermitLimit          = 2,
                    SegmentsPerWindow    = 2,
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit           = 0
                }));

        // Auth login: 5 req/min per IP — chống Brute Force
        options.AddPolicy("auth", httpContext =>
            RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: GetClientPartitionKey(httpContext, useUserId: false),
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    Window               = TimeSpan.FromMinutes(1),
                    PermitLimit          = 5,
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit           = 0
                }));

        // Check-in: 100 req/min per StaffUserID
        options.AddPolicy("checkin", httpContext =>
            RateLimitPartition.GetFixedWindowLimiter(
                partitionKey: GetClientPartitionKey(httpContext, useUserId: true),
                factory: _ => new FixedWindowRateLimiterOptions
                {
                    Window               = TimeSpan.FromMinutes(1),
                    PermitLimit          = 100,
                    QueueProcessingOrder = QueueProcessingOrder.OldestFirst,
                    QueueLimit           = 0
                }));

        // Response khi bị rate limit
        options.OnRejected = async (ctx, _) =>
        {
            ctx.HttpContext.Response.StatusCode  = StatusCodes.Status429TooManyRequests;
            ctx.HttpContext.Response.ContentType = "application/problem+json";
            await ctx.HttpContext.Response.WriteAsJsonAsync(new
            {
                type   = "https://api.concert.vn/errors/too-many-requests",
                title  = "Too Many Requests",
                status = 429,
                detail = "Quá nhiều yêu cầu. Vui lòng thử lại sau."
            });
        };
    });

    // ── Redis ─────────────────────────────────────────────────────────────────
    var redisConnection = RequireConfig(builder, "Redis:ConnectionString");
    if (!redisConnection.Contains("abortConnect", StringComparison.OrdinalIgnoreCase))
    {
        redisConnection += ",abortConnect=false";
    }
    builder.Services.AddSingleton<IConnectionMultiplexer>(
        ConnectionMultiplexer.Connect(redisConnection));

    // ── Hangfire (cho Email Job — cần retry + persistence) ───────────────────
    builder.Services.AddHangfire(configuration => configuration
        .SetDataCompatibilityLevel(CompatibilityLevel.Version_180)
        .UseSimpleAssemblyNameTypeSerializer()
        .UseRecommendedSerializerSettings()
        .UseSqlServerStorage(connectionString, new SqlServerStorageOptions
        {
            CommandBatchMaxTimeout       = TimeSpan.FromMinutes(5),
            SlidingInvisibilityTimeout   = TimeSpan.FromMinutes(5),
            QueuePollInterval            = TimeSpan.Zero,
            UseRecommendedIsolationLevel = true,
            DisableGlobalLocks           = true,
            PrepareSchemaIfNecessary     = false
        }));
    builder.Services.AddHangfireServer();

    // ── Data access ───────────────────────────────────────────────────────────
    // Mọi connection đi qua factory để SESSION_CONTEXT(N'UserID') được set trước
    // câu lệnh đầu tiên — điều kiện bắt buộc để 4 view RLS và
    // TRG_AuditRecord_SecurityGuard hoạt động (§23.7).
    builder.Services.AddHttpContextAccessor();
    builder.Services.AddScoped<IDbConnectionFactory>(sp =>
        new SqlConnectionFactory(connectionString, sp.GetRequiredService<IHttpContextAccessor>()));

    // ── Repositories (Dapper-based) ───────────────────────────────────────────
    // Cùng yêu cầu độ dài với Jwt:Secret: đây cũng là khóa HMAC-SHA256, và nó là thứ
    // duy nhất ngăn người ngoài tự gọi webhook xác nhận thanh toán.
    var paymentSignatureSecret = RequireConfig(builder, "PaymentSignature:Secret", minLength: 32);

    // ── Cổng thanh toán ──────────────────────────────────────────────────────
    // Simulator = bộ mô phỏng chạy trong chính backend, phục vụ demo khi chưa tích hợp
    // PSP thật. Nó KHÔNG bỏ qua bước xác minh: nó đóng đúng vai của cổng thanh toán —
    // tính chữ ký ở phía máy chủ rồi gọi vào cùng luồng xác nhận, nên demo vẫn chạy qua
    // toàn bộ mã kiểm tra chữ ký thật.
    //
    // Chặn cứng ở Production: cho phép "thanh toán" mà không có tiền thật đi kèm là
    // điều không bao giờ được xuất hiện ngoài môi trường demo/thử nghiệm.
    var paymentMode = builder.Configuration["PaymentGateway:Mode"] ?? "External";
    if (!string.Equals(paymentMode, "Simulator", StringComparison.OrdinalIgnoreCase) &&
        !string.Equals(paymentMode, "External", StringComparison.OrdinalIgnoreCase))
        throw new InvalidOperationException("'PaymentGateway:Mode' phải là 'Simulator' hoặc 'External'.");

    var simulatorMode = string.Equals(paymentMode, "Simulator", StringComparison.OrdinalIgnoreCase);
    if (simulatorMode && builder.Environment.IsProduction())
        throw new InvalidOperationException(
            "PaymentGateway:Mode = 'Simulator' KHÔNG được phép ở môi trường Production. " +
            "Đặt 'External' và cấu hình cổng thanh toán thật.");

    var paymentUrlTemplate = simulatorMode
        ? RequireConfig(builder, "PaymentGateway:SimulatorReturnUrl")
        : RequireConfig(builder, "PaymentGateway:ExternalPaymentUrl");

    builder.Services.AddSingleton(new PaymentGatewaySettings(simulatorMode, paymentUrlTemplate));

    builder.Services.AddScoped<IBookingRepository, BookingRepository>();
    builder.Services.AddScoped<IConcertRepository, ConcertRepository>();
    builder.Services.AddScoped<ICheckInRepository, CheckInRepository>();
    builder.Services.AddScoped<IUserRepository, UserRepository>();
    builder.Services.AddScoped<IPaymentRepository>(sp =>
        new PaymentRepository(
            sp.GetRequiredService<IDbConnectionFactory>(),
            paymentSignatureSecret,
            sp.GetRequiredService<PaymentGatewaySettings>()));
    builder.Services.AddScoped<IAdminRepository, AdminRepository>();
    builder.Services.AddScoped<IWaitlistRepository, WaitlistRepository>();
    builder.Services.AddScoped<IQueueRepository, QueueRepository>();

    // ── Application Services ──────────────────────────────────────────────────
    builder.Services.AddScoped<IAuthService, AuthService>();

    // ── Cache ─────────────────────────────────────────────────────────────────
    var seatMapTtl = builder.Configuration.GetValue<int>("Redis:SeatMapTtlSeconds", 15);
    builder.Services.AddSingleton<ISeatMapCache>(sp =>
        new SeatMapCache(
            sp.GetRequiredService<IConnectionMultiplexer>(),
            sp.GetRequiredService<IServiceScopeFactory>(),
            seatMapTtl,
            sp.GetRequiredService<ILogger<SeatMapCache>>()));

    // ── Background Workers: một tiến trình định kỳ cho mỗi SIP (§24.3) ────────
    // Dùng IHostedService (không phải Hangfire) vì đây là job định kỳ đơn giản,
    // không cần retry hay persistence — mọi SP đều idempotent theo BR49a.
    // Các worker chạy ngoài HTTP request nên dùng OpenForSystemAsync (ActorUserID = 'system', D14).
    // SIP4 KHÔNG có worker: chạy đồng bộ ngay trong sp_UpdateConcertStatus.
    var workerFactory = (IServiceProvider sp) =>
        (IDbConnectionFactory)new SqlConnectionFactory(
            connectionString, sp.GetRequiredService<IHttpContextAccessor>());

    // SIP1 + SIP2 — nhả hold hết hạn rồi cấp ngay cho Waitlist
    builder.Services.AddHostedService(sp =>
        new HoldReleaseWorker(workerFactory(sp),
            sp.GetRequiredService<ILogger<HoldReleaseWorker>>()));

    // SIP3 — admission hàng đợi Fair Access
    builder.Services.AddHostedService(sp =>
        new QueueAdmissionWorker(workerFactory(sp),
            sp.GetRequiredService<ILogger<QueueAdmissionWorker>>()));

    // SIP5 — tự động mở/đóng bán vé theo lịch
    builder.Services.AddHostedService(sp =>
        new SaleWindowWorker(workerFactory(sp),
            sp.GetRequiredService<ILogger<SaleWindowWorker>>()));

    // ── Health Checks ─────────────────────────────────────────────────────────
    builder.Services.AddHealthChecks()
        .AddSqlServer(connectionString, name: "sqlserver")
        .AddRedis(redisConnection, name: "redis");

    // ─────────────────────────────────────────────────────────────────────────
    var app = builder.Build();
    // ─────────────────────────────────────────────────────────────────────────

    // ── THỨ TỰ MIDDLEWARE RẤT QUAN TRỌNG ────────────────────────────────────
    app.UseForwardedHeaders(new ForwardedHeadersOptions
    {
        ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto
    });

    // 1. Request Logging (trước hết, log mọi request vào)
    app.UseSerilogRequestLogging();

    // 2. Error Handling (bao bọc toàn bộ pipeline)
    app.UseMiddleware<ErrorHandlingMiddleware>();

    // 3. HTTPS Redirect
    if (!app.Environment.IsDevelopment())
        app.UseHttpsRedirection();

    // 3.5 CORS (phải TRƯỚC Routing/Auth)
    app.UseCors("AllowFrontend");

    // 4. Routing
    app.UseRouting();

    // 5. Authentication (phải TRƯỚC Authorization và RateLimiter UserID-based)
    app.UseAuthentication();
    app.UseAuthorization();

    // 6. Rate Limiter (phải SAU Authentication để UserID-based limiter hoạt động)
    app.UseRateLimiter();

    // 7. Controllers
    app.MapControllers();

    // 8. Hangfire Dashboard (chỉ Admin)
    app.MapHangfireDashboard("/hangfire", new DashboardOptions
    {
        Authorization = new[] { new HangfireAdminAuthFilter() }
    });

    // 9. OpenAPI / Scalar (chỉ Development)
    if (app.Environment.IsDevelopment())
    {
        app.MapOpenApi();
        app.MapScalarApiReference(options =>
        {
            options.Title = "Concert Ticketing API";
            options.Theme = ScalarTheme.DeepSpace;
            // Cho phép nhập JWT token trực tiếp trên Scalar UI
            options.Authentication = new ScalarAuthenticationOptions
            {
                PreferredSecuritySchemes = ["Bearer"]
            };
        });
    }

    // 10. Health Check
    app.MapHealthChecks("/healthz");

    app.Run();

    // ── Local Helper: partition key cho Rate Limiter ───────────────────────────
    static string GetClientPartitionKey(HttpContext httpContext, bool useUserId)
    {
        // UserID từ JWT nếu có (rate limit theo user); fallback theo IP.
        if (useUserId)
        {
            var sub = httpContext.User.FindFirstValue(System.Security.Claims.ClaimTypes.NameIdentifier)
                   ?? httpContext.User.FindFirstValue("sub");
            if (!string.IsNullOrEmpty(sub))
                return "u:" + sub;
        }
        var ip = httpContext.Connection.RemoteIpAddress?.ToString() ?? "unknown";
        return "ip:" + ip;
    }
}
catch (Exception ex)
{
    Log.Fatal(ex, "Application startup failed.");
    throw;
}
finally
{
    Log.CloseAndFlush();
}
