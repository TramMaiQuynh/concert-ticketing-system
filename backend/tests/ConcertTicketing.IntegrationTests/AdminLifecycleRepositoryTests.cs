using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho các đường ghi vòng đời vừa được bổ sung ở tầng DB
/// (FR59b/BR50e, FR64a, FR52/FR53b, BR39, FR12).
///
/// Mục đích kép:
///  1. Chứng minh mọi giá trị trạng thái trong lược đồ đều có bên ghi thật (§24.4) —
///     trước đây Retired/Inactive/Disabled/Revoked/RANDOM tồn tại trong CHECK constraint
///     nhưng không SP hay endpoint nào đặt được.
///  2. Bắt sai lệch TÊN THAM SỐ giữa repository và stored procedure — lớp lỗi chỉ lộ ra
///     khi gọi thật vào DB, không thể phát hiện bằng unit test.
/// </summary>
public sealed class AdminLifecycleRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public AdminLifecycleRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private AdminRepository Repo() => new(_fx.ApiFactory);

    // ── Vòng đời danh mục: Venue / Zone / Seat ────────────────────────────────

    [Fact(DisplayName = "UpdateVenue/Zone/Seat: chuyển được sang Inactive/Retired (FR59b)")]
    public async Task CatalogLifecycle_RetireWorks()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var repo = Repo();

        var venueId = await repo.CreateVenueAsync(admin, new CreateVenueRequest(s.VenueName, "IT Address"));
        var zoneId = await repo.CreateZoneAsync(admin, venueId, new CreateZoneRequest(s.ZoneCode, s.ZoneCode));
        // Hàng/cột là BẮT BUỘC với ghế trong khu có ghế (sp_CreateSeat, 59825): thiếu vị
        // trí thì sơ đồ dồn mọi ghế về cùng một ô lưới và chúng chồng khít lên nhau.
        var seatId = await repo.CreateSeatAsync(admin, zoneId,
            new CreateSeatRequest(s.SeatCode, "IT-Seat", SeatRowLabel: "A", SeatColumnNumber: 1));

        await repo.UpdateSeatAsync(admin, seatId, new UpdateSeatRequest(SeatStatus: "Retired"));
        await repo.UpdateZoneAsync(admin, zoneId, new UpdateZoneRequest(ZoneStatus: "Retired"));
        await repo.UpdateVenueAsync(admin, venueId, new UpdateVenueRequest(VenueStatus: "Inactive"));

        (await _fx.QueryAdminAsync<string>("SELECT SeatStatus FROM Seat WHERE SeatID = @id", new { id = seatId }))
            .Should().Be("Retired");
        (await _fx.QueryAdminAsync<string>("SELECT ZoneStatus FROM Zone WHERE ZoneID = @id", new { id = zoneId }))
            .Should().Be("Retired");
        (await _fx.QueryAdminAsync<string>("SELECT VenueStatus FROM Venue WHERE VenueID = @id", new { id = venueId }))
            .Should().Be("Inactive");
    }

    [Fact(DisplayName = "UpdateArtist: chuyển được sang Retired (FR59b)")]
    public async Task UpdateArtist_RetireWorks()
    {
        // UpdateArtistAsync truoc day KHONG co integration test nao, nghia la duong
        // Dapper -> sp_UpdateArtist (rieng tham so @ArtistStatus) chua tung duoc chay
        // that lan nao. Bo sung de khep lo hong do: day la tham so duy nhat trong 24
        // cho vua sua kieu DbType ma khong co bai kiem nao cham toi.
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var repo = Repo();

        var artistId = await repo.CreateArtistAsync(admin, new CreateArtistRequest($"IT-Artist-{Guid.NewGuid():N}"));

        await repo.UpdateArtistAsync(admin, artistId, new UpdateArtistRequest(ArtistStatus: "Retired"));

        (await _fx.QueryAdminAsync<string>("SELECT ArtistStatus FROM Artist WHERE ArtistID = @id", new { id = artistId }))
            .Should().Be("Retired");
    }

    [Fact(DisplayName = "UpdateSeat: Retire ghế đang nằm trong kho vé Concert chưa kết thúc → 59425")]
    public async Task RetireSeatInUse_Throws59425()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        var act = () => Repo().UpdateSeatAsync(baseline.AdminUserId, baseline.SeatId1,
            new UpdateSeatRequest(SeatStatus: "Retired"));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 59425);
    }

    [Fact(DisplayName = "UpdateVenue: Customer (không phải Admin) → 59401")]
    public async Task UpdateVenue_NonAdmin_Throws59401()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var customer = await s.CreateUserAsync("Customer");
        var repo = Repo();

        var venueId = await repo.CreateVenueAsync(admin, new CreateVenueRequest(s.VenueName, "x"));

        var act = () => repo.UpdateVenueAsync(customer, venueId, new UpdateVenueRequest(VenueStatus: "Inactive"));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 59401);
    }

    // ── Cấu hình Fair Access / Waitlist theo Concert (FR64a) ──────────────────

    [Fact(DisplayName = "ConfigureQueue: đặt được RANDOM + capacity + booking_ttl riêng cho Concert")]
    public async Task ConfigureQueue_SetsRandomPolicyAndTtl()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s, fairAccess: true);

        await Repo().ConfigureQueueAsync(baseline.AdminUserId, baseline.ConcertId,
            new ConfigureQueueRequest(
                AdmissionCapacity: 250,
                FairAccessPolicy: "RANDOM",
                AdmissionValiditySeconds: 300));

        var row = await _fx.QueryAdminAsync<int>(
            @"SELECT COUNT(*) FROM Queue
              WHERE ConcertID = @cid AND FairAccessPolicy = 'RANDOM'
                AND AdmissionCapacity = 250 AND AdmissionValiditySeconds = 300",
            new { cid = baseline.ConcertId });
        row.Should().Be(1);
    }

    [Fact(DisplayName = "ConfigureQueue: Concert chưa bật FairAccessEnabled → 59507")]
    public async Task ConfigureQueue_FairAccessOff_Throws59507()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s, fairAccess: false);

        var act = () => Repo().ConfigureQueueAsync(baseline.AdminUserId, baseline.ConcertId,
            new ConfigureQueueRequest(AdmissionCapacity: 10));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 59507);
    }

    [Fact(DisplayName = "ConfigureWaitlist: đặt được AllocationPolicy = RANDOM (BR43)")]
    public async Task ConfigureWaitlist_SetsRandomPolicy()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s, waitlistEnabled: true);

        await Repo().ConfigureWaitlistAsync(baseline.AdminUserId, baseline.ConcertId,
            new ConfigureWaitlistRequest(AllocationPolicy: "RANDOM"));

        var policy = await _fx.QueryAdminAsync<string>(
            "SELECT AllocationPolicy FROM Waitlist WHERE ConcertID = @cid",
            new { cid = baseline.ConcertId });
        policy.Should().Be("RANDOM");
    }

    // ── Vòng đời khuyến mãi / mã giảm giá (FR52, FR53b) ──────────────────────

    [Fact(DisplayName = "UpdatePromotionStatus + UpdateDiscountCodeStatus: thu hồi được chương trình và mã")]
    public async Task PromotionLifecycle_DisableWorks()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var repo = Repo();

        var promoId = await repo.CreatePromotionAsync(baseline.AdminUserId, baseline.ConcertId,
            new CreatePromotionRequest(
                s.PromotionName, "desc", "FIXED", 10000,
                DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1),
                UsageLimit: 100, CodeRequiredFlag: true));
        var codeId = await repo.CreateDiscountCodeAsync(baseline.AdminUserId, promoId,
            new CreateDiscountCodeRequest(s.DiscountCodeValue));

        await repo.UpdatePromotionStatusAsync(baseline.AdminUserId, promoId, "Disabled");
        await repo.UpdateDiscountCodeStatusAsync(baseline.AdminUserId, codeId, "Disabled");

        (await _fx.QueryAdminAsync<string>(
            "SELECT PromotionStatus FROM Promotion WHERE PromotionID = @id", new { id = promoId }))
            .Should().Be("Disabled");
        (await _fx.QueryAdminAsync<string>(
            "SELECT CodeStatus FROM DiscountCode WHERE DiscountCodeID = @id", new { id = codeId }))
            .Should().Be("Disabled");
    }

    [Fact(DisplayName = "UpdatePromotionStatus: đưa Promotion đã công bố về Draft → 59604")]
    public async Task UpdatePromotionStatus_BackToDraft_Throws59604()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var repo = Repo();

        var promoId = await repo.CreatePromotionAsync(baseline.AdminUserId, baseline.ConcertId,
            new CreatePromotionRequest(
                s.PromotionName, "desc", "FIXED", 10000,
                DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1),
                UsageLimit: 100, CodeRequiredFlag: false));

        var act = () => repo.UpdatePromotionStatusAsync(baseline.AdminUserId, promoId, "Draft");
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 59604);
    }

    // ── Trạng thái hạng vé (FR12) ────────────────────────────────────────────

    [Fact(DisplayName = "ConfigureTicketCategory: chuyển được CategoryStatus sang Inactive")]
    public async Task TicketCategory_SetInactive()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var organizer = await s.CreateUserAsync("Organizer");
        var artist = await s.CreateArtistAsync();
        var venue = await s.CreateVenueAsync();
        var concertId = await s.CreateConcertDraftAsync(organizer, artist, venue);
        var repo = Repo();

        var catId = await repo.ConfigureTicketCategoryAsync(admin, concertId,
            new ConfigureTicketCategoryRequest(s.CategoryName, "desc", 250000));

        await repo.ConfigureTicketCategoryAsync(admin, concertId,
            new ConfigureTicketCategoryRequest(s.CategoryName, "desc", 250000,
                TicketCategoryId: catId, CategoryStatus: "Inactive"));

        var status = await _fx.QueryAdminAsync<string>(
            "SELECT CategoryStatus FROM TicketCategory WHERE TicketCategoryID = @id", new { id = catId });
        status.Should().Be("Inactive");
    }

    // ── Thu hồi phân công Check-in Staff (BR39 / FR51) ───────────────────────

    [Fact(DisplayName = "AddCheckinStaffAssignment: thu hồi rồi gán lại được (BR39)")]
    public async Task CheckinStaffAssignment_RevokeAndReassign()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var staff = await s.CreateUserAsync("Check-in Staff");
        var repo = Repo();

        await repo.AddCheckinStaffAssignmentAsync(baseline.AdminUserId,
            new AddCheckinStaffAssignmentRequest(staff, new List<int> { baseline.ConcertId }));

        await repo.AddCheckinStaffAssignmentAsync(baseline.AdminUserId,
            new AddCheckinStaffAssignmentRequest(staff, new List<int> { baseline.ConcertId }, "Revoked"));

        (await _fx.QueryAdminAsync<string>(
            "SELECT AssignmentStatus FROM CheckinStaffAssignment WHERE UserID = @u AND ConcertID = @c",
            new { u = staff, c = baseline.ConcertId }))
            .Should().Be("Revoked");

        await repo.AddCheckinStaffAssignmentAsync(baseline.AdminUserId,
            new AddCheckinStaffAssignmentRequest(staff, new List<int> { baseline.ConcertId }, "Active"));

        (await _fx.QueryAdminAsync<string>(
            "SELECT AssignmentStatus FROM CheckinStaffAssignment WHERE UserID = @u AND ConcertID = @c",
            new { u = staff, c = baseline.ConcertId }))
            .Should().Be("Active");
    }
}
