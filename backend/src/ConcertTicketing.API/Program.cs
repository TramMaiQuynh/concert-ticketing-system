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
using ConcertTicketing.Infrastructure.Repositories;

// ── Bootstrap Serilog sớm để bắt lỗi khởi động ────────────────────────────
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .CreateBootstrapLogger();

try
{
    var builder = WebApplication.CreateBuilder(args);

    // ── Serilog ───────────────────────────────────────────────────────────────
    builder.Host.UseSerilog((ctx, services, config) =>
        config.ReadFrom.Configuration(ctx.Configuration)
              .ReadFrom.Services(services));

    var connectionString = builder.Configuration.GetConnectionString("Default")!;

    // ── CORS ─────────────────────────────────────────────────────────────────
    builder.Services.AddCors(options =>
    {
        options.AddPolicy("AllowFrontend", policy =>
        {
            policy.WithOrigins("http://localhost:5173", "http://127.0.0.1:5173")
                  .AllowAnyHeader()
                  .AllowAnyMethod()
                  .AllowCredentials(); // Required for HttpOnly Cookies (Refresh Token)
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
    var jwtSecret   = builder.Configuration["Jwt:Secret"]!;
    var jwtIssuer   = builder.Configuration["Jwt:Issuer"]!;
    var jwtAudience = builder.Configuration["Jwt:Audience"]!;

    // C3 fix: Từ chối khởi động nếu JWT Secret không đủ mạnh/bị bỏ trống.
    if (string.IsNullOrEmpty(jwtSecret) || jwtSecret.Length < 32)
        throw new InvalidOperationException("Jwt:Secret phải được cấu hình hợp lệ với độ dài >= 32 ký tự (256-bit).");

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
    var redisConnection = builder.Configuration["Redis:ConnectionString"]!;
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

    // ── Repositories (Dapper-based) ───────────────────────────────────────────
    var paymentSignatureSecret = builder.Configuration["PaymentSignature:Secret"]
        ?? throw new InvalidOperationException("PaymentSignature:Secret phải được cấu hình.");

    builder.Services.AddScoped<IBookingRepository>(_ =>
        new BookingRepository(connectionString));
    builder.Services.AddScoped<IConcertRepository>(_ =>
        new ConcertRepository(connectionString));
    builder.Services.AddScoped<ICheckInRepository>(_ =>
        new CheckInRepository(connectionString));
    builder.Services.AddScoped<IUserRepository>(_ =>
        new UserRepository(connectionString));
    builder.Services.AddScoped<IPaymentRepository>(_ =>
        new PaymentRepository(connectionString, paymentSignatureSecret));
    builder.Services.AddScoped<IAdminRepository>(_ =>
        new AdminRepository(connectionString));
    builder.Services.AddScoped<IWaitlistRepository>(_ =>
        new WaitlistRepository(connectionString));
    builder.Services.AddScoped<IQueueRepository>(_ =>
        new QueueRepository(connectionString));

    // ── Application Services ──────────────────────────────────────────────────
    builder.Services.AddScoped<IAuthService, AuthService>();

    // ── Cache ─────────────────────────────────────────────────────────────────
    var seatMapTtl = builder.Configuration.GetValue<int>("Redis:SeatMapTtlSeconds", 15);
    builder.Services.AddSingleton<ISeatMapCache>(sp =>
        new SeatMapCache(
            sp.GetRequiredService<IConnectionMultiplexer>(),

            sp.GetRequiredService<IServiceScopeFactory>(),
            seatMapTtl));

    // ── Background Worker: HoldRelease + Waitlist Allocation (IHostedService) ─
    // Dùng IHostedService (không phải Hangfire) vì đây là job định kỳ đơn giản,
    // không cần retry hay persistence.
    builder.Services.AddHostedService(sp =>
        new HoldReleaseWorker(
            connectionString,
            sp.GetRequiredService<ILogger<HoldReleaseWorker>>()));

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
