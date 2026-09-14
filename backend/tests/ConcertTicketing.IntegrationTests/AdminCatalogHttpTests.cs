using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using System.Text.Json;
using ConcertTicketing.API.Controllers;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Infrastructure.Data;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using ConcertTicketing.Application.Validators;
using FluentValidation;
using FluentValidation.AspNetCore;
using FluentAssertions;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Hosting.Server;
using Microsoft.AspNetCore.Hosting.Server.Features;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;

namespace ConcertTicketing.IntegrationTests;

public sealed class AdminCatalogHttpTests(DbFixture fx) : IClassFixture<DbFixture>
{
    [Fact]
    public async Task GetCatalogs_ValidateQueries_EnforceHttpRoles_AndScopeDatabaseRows()
    {
        var seed = new TestDataSeeder(fx);
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(seed);
        var stranger = await seed.CreateUserAsync("Organizer", instance: 9);
        var key = new SymmetricSecurityKey(Encoding.UTF8.GetBytes("catalog-http-test-key-not-used-in-production-2026"));
        var builder = WebApplication.CreateBuilder();
        builder.Logging.ClearProviders();
        builder.WebHost.ConfigureKestrel(options => options.Listen(IPAddress.Loopback, 0));
        builder.Services.AddControllers().AddApplicationPart(typeof(AdminController).Assembly);
        builder.Services.AddFluentValidationAutoValidation();
        builder.Services.AddValidatorsFromAssemblyContaining<CreateBookingValidator>();
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddScoped<IDbConnectionFactory>(services => new SqlConnectionFactory(
            fx.ApiConnectionString, services.GetRequiredService<Microsoft.AspNetCore.Http.IHttpContextAccessor>()));
        builder.Services.AddScoped<IAdminRepository, AdminRepository>();
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(options =>
            options.TokenValidationParameters = new TokenValidationParameters
            {
                ValidateIssuer = false, ValidateAudience = false, ValidateLifetime = true,
                ValidateIssuerSigningKey = true, IssuerSigningKey = key
            });
        builder.Services.AddAuthorization();
        await using var app = builder.Build();
        app.UseAuthentication();
        app.UseAuthorization();
        app.MapControllers();
        await app.StartAsync();
        var address = app.Services.GetRequiredService<IServer>().Features
            .Get<IServerAddressesFeature>()!.Addresses.Single();
        using var client = new HttpClient { BaseAddress = new Uri(address) };

        void SignIn(int userId, string role)
        {
            var token = new JwtSecurityToken(claims: [
                new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                new Claim(ClaimTypes.Role, role)
            ], expires: DateTime.UtcNow.AddMinutes(5),
                signingCredentials: new SigningCredentials(key, SecurityAlgorithms.HmacSha256));
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue(
                "Bearer", new JwtSecurityTokenHandler().WriteToken(token));
        }

        foreach (var route in new[] { "concerts", "zones", "seats", "categories", "promotions", "discount-codes", "refunds" })
        {
            client.DefaultRequestHeaders.Authorization = null;
            (await client.GetAsync("/api/admin/" + route)).StatusCode.Should().Be(HttpStatusCode.Unauthorized);
            SignIn(baseline.CustomerUserId, "Customer");
            (await client.GetAsync("/api/admin/" + route)).StatusCode.Should().Be(HttpStatusCode.Forbidden);
            SignIn(baseline.OrganizerUserId, "Organizer");
            var response = await client.GetAsync("/api/admin/" + route);
            response.StatusCode.Should().Be(HttpStatusCode.OK, await response.Content.ReadAsStringAsync());
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync());
            json.RootElement.ValueKind.Should().Be(JsonValueKind.Array);
        }
        foreach (var query in new[] { "limit=0", "limit=201", "afterId=-1", "concertId=0", "venueId=-1", "zoneId=0", "promotionId=0" })
            (await client.GetAsync("/api/admin/categories?" + query)).StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var categoryPath = "/api/admin/categories?concertId=" + baseline.ConcertId;
        var ownerJson = await client.GetStringAsync(categoryPath);
        using (var json = JsonDocument.Parse(ownerJson))
        {
            json.RootElement.GetArrayLength().Should().Be(1);
            json.RootElement[0].GetProperty("ticketCategoryID").GetInt32().Should().Be(baseline.CategoryId);
        }
        SignIn(baseline.OrganizerUserId, "Organizer");
        var artistPath = "/api/admin/concerts/" + baseline.ConcertId + "/artists";
        using (var json = JsonDocument.Parse(await client.GetStringAsync(artistPath)))
        {
            json.RootElement.GetArrayLength().Should().Be(1);
            json.RootElement[0].GetProperty("artistID").GetInt32().Should().Be(baseline.ArtistId);
            json.RootElement[0].GetProperty("artistOrder").GetInt32().Should().Be(1);
        }
        SignIn(stranger, "Organizer");
        (await client.GetStringAsync(categoryPath + "&organizerId=" + baseline.OrganizerUserId)).Should().Be("[]");
        (await client.GetStringAsync(artistPath)).Should().Be("[]");
        SignIn(baseline.AdminUserId, "Admin");
        (await client.GetStringAsync(categoryPath)).Should().Be(ownerJson);

        // ── Venue: validator phải THẬT SỰ được thi hành trên đường HTTP ──────
        // CreateVenueValidator/UpdateVenueValidator nằm trong assembly được quét bởi
        // AddValidatorsFromAssemblyContaining<CreateBookingValidator>() ở trên, nên
        // đăng ký qua DI. Kiểm bằng request thật thay vì tin vào suy luận: chuỗi
        // validator → ModelState → 400 chỉ có giá trị nếu nó chạy.
        //
        // Không kiểm gì thì ADO.NET CẮT chuỗi vượt `size` (255/500) một cách im lặng
        // — repository gửi size khớp cột, nên tên bị lưu cụt mà không có lỗi nào.
        var tooLongName = await client.PutAsJsonAsync($"/api/admin/venues/{baseline.VenueId}",
            new { venueName = new string('a', 256) });
        tooLongName.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        var tooLongAddress = await client.PutAsJsonAsync($"/api/admin/venues/{baseline.VenueId}",
            new { address = new string('a', 501) });
        tooLongAddress.StatusCode.Should().Be(HttpStatusCode.BadRequest);

        // Bỏ trống hết = "giữ nguyên mọi trường" (COALESCE trong sp_UpdateVenue):
        // phải đi qua được validator và trả 204, không đổi dữ liệu.
        var keepEverything = await client.PutAsJsonAsync($"/api/admin/venues/{baseline.VenueId}",
            new { });
        keepEverything.StatusCode.Should().Be(HttpStatusCode.NoContent);

        // Thêm validator KHÔNG được nới lỏng phân quyền: route mang
        // [Authorize(Roles = "Admin")] nên Organizer vẫn bị 403.
        SignIn(baseline.OrganizerUserId, "Organizer");
        var forbidden = await client.PutAsJsonAsync($"/api/admin/venues/{baseline.VenueId}",
            new { venueName = "Doi ten trai phep" });
        forbidden.StatusCode.Should().Be(HttpStatusCode.Forbidden);

        // ── StagePass: cùng lớp lỗi, đo được bằng test thật ─────────────────
        // Cột TemplateFloor.FloorKey là varchar(64) và repository khai `size: 64` (khớp).
        // Nhưng `size` cũng là độ dài ADO.NET CẮT giá trị trước khi gửi: đo trực tiếp
        // bằng integration test (gửi FloorKey 100 ký tự) cho thấy DB nhận ĐÚNG 64 ký tự
        // và KHÔNG có lỗi nào — người dùng gõ dài bị mất chữ mà không được báo. Sáu SP
        // StagePass đều KHÔNG kiểm độ dài (đã quét toàn bộ), nên tầng API là chốt duy
        // nhất. Không có test này thì việc "thêm MaximumLength" chỉ là niềm tin.
        var stagePassRepo = new AdminRepository(fx.ApiFactory);
        var templateId = await stagePassRepo.CreateVenueTemplateAsync(baseline.AdminUserId,
            baseline.VenueId, new CreateVenueTemplateRequest($"IT-Http-Tpl-{fx.Suffix}"));
        var versionId = await stagePassRepo.CreateVenueTemplateVersionAsync(baseline.AdminUserId,
            templateId, new CreateVenueTemplateVersionRequest(CopyFromVersionID: null));

        SignIn(baseline.AdminUserId, "Admin");
        var floorPath = $"/api/admin/template-versions/{versionId}/floors";

        var longFloorKey = await client.PostAsJsonAsync(floorPath, new
        {
            templateFloorID = (int?)null,
            floorKey = new string('K', 100),
            floorOrder = 1,
            canvasWidth = 800,
            canvasHeight = 600
        });
        longFloorKey.StatusCode.Should().Be(HttpStatusCode.BadRequest,
            await longFloorKey.Content.ReadAsStringAsync());

        var validFloorKey = await client.PostAsJsonAsync(floorPath, new
        {
            templateFloorID = (int?)null,
            floorKey = "ground",
            floorOrder = 1,
            canvasWidth = 800,
            canvasHeight = 600
        });
        validFloorKey.StatusCode.Should().Be(HttpStatusCode.Created,
            await validFloorKey.Content.ReadAsStringAsync());

        // ── Ghế: chỗ này ĐO ĐƯỢC cơ chế, không phải suy luận từ việc đọc code ──
        // Cột Seat.SeatLabel là nvarchar(255) (sys.columns: 510 byte / 2) và repository
        // khai `size: 255`, nên `size` vừa khớp cột vừa là độ dài bị CẮT trên đường
        // truyền. Đo bằng chính repository trên database thật trước khi thêm validator:
        //     tạo ghế với SeatLabel 300 ký tự -> DB lưu đúng 255, KHÔNG lỗi nào
        //     sửa ghế với SeatLabel 400 ký tự -> DB lưu đúng 255, KHÔNG lỗi nào
        // Đường PUT khi đó thậm chí không có validator nào (UpdateSeatValidator không
        // tồn tại) và sp_UpdateSeat cũng không có LEN(). Hai cặp assertion dưới đây
        // chứng minh chốt ở tầng API đã đóng cho CẢ HAI đường, và GIỮ NGUYÊN giá trị
        // đúng giới hạn (255) — tức là không siết quá tay.
        var seatPath = $"/api/admin/zones/{baseline.ZoneId}/seats";

        var longSeatLabel = await client.PostAsJsonAsync(seatPath, new
        {
            seatCode = $"IT-{fx.Suffix}-LONG",
            seatLabel = new string('L', 256),
            seatRowLabel = "Z",
            seatColumnNumber = 99
        });
        longSeatLabel.StatusCode.Should().Be(HttpStatusCode.BadRequest,
            await longSeatLabel.Content.ReadAsStringAsync());

        var atLimitSeatLabel = await client.PostAsJsonAsync(seatPath, new
        {
            seatCode = $"IT-{fx.Suffix}-OK",
            seatLabel = new string('L', 255),
            seatRowLabel = "Z",
            seatColumnNumber = 98
        });
        atLimitSeatLabel.StatusCode.Should().Be(HttpStatusCode.Created,
            await atLimitSeatLabel.Content.ReadAsStringAsync());
        var createdSeatId = (await atLimitSeatLabel.Content.ReadFromJsonAsync<IdResponse>())!.Id;

        var longLabelUpdate = await client.PutAsJsonAsync($"/api/admin/seats/{createdSeatId}",
            new { seatLabel = new string('M', 256) });
        longLabelUpdate.StatusCode.Should().Be(HttpStatusCode.BadRequest,
            await longLabelUpdate.Content.ReadAsStringAsync());

        var atLimitUpdate = await client.PutAsJsonAsync($"/api/admin/seats/{createdSeatId}",
            new { seatLabel = new string('M', 255) });
        atLimitUpdate.StatusCode.Should().Be(HttpStatusCode.NoContent,
            await atLimitUpdate.Content.ReadAsStringAsync());

        // 17 ký tự cho HÀNG: cột Seat.SeatRowLabel là nvarchar(16), và sp_UpdateSeat
        // không kiểm độ dài — nên tầng API là chốt duy nhất.
        var longRowUpdate = await client.PutAsJsonAsync($"/api/admin/seats/{createdSeatId}",
            new { seatRowLabel = new string('R', 17), seatColumnNumber = 1 });
        longRowUpdate.StatusCode.Should().Be(HttpStatusCode.BadRequest,
            await longRowUpdate.Content.ReadAsStringAsync());

        // ── Tạo hàng loạt NHIỀU HÀNG, đúng hình dạng mã lib/seatCode.js sinh ra ──
        // Mã ghế là duy nhất trong một khu, nên nếu mã không chứa hàng thì hai hàng khác
        // nhau sẽ sinh ra mã trùng và sp_CreateSeatsBatch từ chối NGUYÊN LÔ (59827). Test
        // này chứng minh chuỗi giao diện → API → stored procedure cho nhiều hàng là THẬT.
        var batchSeats = new[] { "A", "B", "C" }
            .SelectMany(row => Enumerable.Range(1, 3).Select(n => new
            {
                seatCode = $"Vip-{row}{n}",
                seatLabel = $"Vip-{row}{n}",
                seatRowLabel = row,
                seatColumnNumber = n
            }))
            .ToArray();

        var multiRowBatch = await client.PostAsJsonAsync(
            $"/api/admin/zones/{baseline.ZoneId}/seats/batch", new { seats = batchSeats });
        multiRowBatch.StatusCode.Should().Be(HttpStatusCode.NoContent,
            await multiRowBatch.Content.ReadAsStringAsync());

        var createdByBatch = await fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Seat WHERE ZoneID = @z AND SeatRowLabel IN ('A','B','C') "
            + "AND SeatColumnNumber BETWEEN 1 AND 3", new { z = baseline.ZoneId });
        createdByBatch.Should().Be(9, "3 hàng × 3 số phải tạo đủ 9 ghế");

        // Mã không trùng vì có hàng trong mã — đây chính là điều 59827 kiểm tra.
        var distinctCodes = await fx.QueryAdminAsync<int>(
            "SELECT COUNT(DISTINCT SeatCode) FROM Seat WHERE ZoneID = @z "
            + "AND SeatRowLabel IN ('A','B','C')", new { z = baseline.ZoneId });
        distinctCodes.Should().Be(9, "9 ghế phải có 9 mã khác nhau");

        // Nhãn phải được LƯU bằng chính mã ghế (không phải NULL): giao diện bỏ ô nhập nhãn
        // khỏi form tạo và đặt nhãn tự động, nên phải chứng minh nó thật sự xuống tới DB.
        var labelledSeats = await fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Seat WHERE ZoneID = @z AND SeatRowLabel IN ('A','B','C') "
            + "AND SeatLabel = SeatCode", new { z = baseline.ZoneId });
        labelledSeats.Should().Be(9, "mọi ghế sinh ra phải có nhãn bằng mã");

        await app.StopAsync();
    }
}
