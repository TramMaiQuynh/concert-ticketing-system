using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho AdminRepository (chạy với connection API thật):
/// - Concert CRUD + state machine Draft→Published→OnSale + invalid 50001
/// - Venue/Zone/Seat (chỉ Admin — actor Customer → 58101)
/// - Category + AddEventSeats
/// - Promotion + DiscountCode
/// - AssignRole (chỉ Admin — 58401)
/// - UpdateUserStatus (chỉ Admin — 58901)
/// - AddCheckinStaffAssignment (chỉ Admin — 59001)
/// </summary>
public sealed class AdminRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public AdminRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private AdminRepository Repo() => new(_fx.ApiConnectionString);

    private async Task<(TestDataSeeder s, int admin, int artist, int venue, int concertId)>
        CreateDraftConcertAsync()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var artist = await s.CreateArtistAsync();
        var venue = await s.CreateVenueAsync();
        var start = DateTime.UtcNow.AddDays(1);
        var concertId = await Repo().CreateConcertAsync(admin, new CreateConcertRequest(
            artist, venue, s.ConcertName, start, start.AddHours(3), ConcertStatus: "Draft"));
        return (s, admin, artist, venue, concertId);
    }

    // ── Concert CRUD + status state machine ────────────────────────────────────

    [Fact(DisplayName = "CreateConcert: tạo ở Draft; UpdateConcert: đổi tên; UpdateStatus: Draft→Published→OnSale")]
    public async Task CreateConcert_Update_StatusFlow_Succeeds()
    {
        var (s, admin, _, _, concertId) = await CreateDraftConcertAsync();
        var repo = Repo();

        await repo.UpdateConcertAsync(concertId, admin, new UpdateConcertRequest(
            ConcertName: s.ConcertName + "-updated"));

        var name = await _fx.QueryAdminAsync<string>(
            "SELECT ConcertName FROM Concert WHERE ConcertID = @id", new { id = concertId });
        name.Should().Be(s.ConcertName + "-updated");

        await repo.UpdateConcertStatusAsync(concertId, admin, "Published");
        await repo.UpdateConcertStatusAsync(concertId, admin, "OnSale");

        var status = await _fx.QueryAdminAsync<string>(
            "SELECT ConcertStatus FROM Concert WHERE ConcertID = @id", new { id = concertId });
        status.Should().Be("OnSale");
    }

    [Fact(DisplayName = "UpdateConcertStatus: chuyển không hợp lệ (Draft→OnSale) → SqlException 50001 (HTTP 409)")]
    public async Task UpdateConcertStatus_InvalidTransition_Throws50001()
    {
        var (_, admin, _, _, concertId) = await CreateDraftConcertAsync();
        var repo = Repo();

        // Draft → OnSale (bỏ qua Published) là transition không hợp lệ theo state machine
        var act = () => repo.UpdateConcertStatusAsync(concertId, admin, "OnSale");
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 50001);
    }

    // ── Venue / Zone / Seat: chỉ Admin ─────────────────────────────────────────

    [Fact(DisplayName = "CreateVenue/CreateZone/CreateSeat: Admin tạo thành công")]
    public async Task Venue_Zone_Seat_AdminCreates()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var repo = Repo();

        var venueId = await repo.CreateVenueAsync(admin, new CreateVenueRequest(s.VenueName, "IT Address"));
        venueId.Should().BeGreaterThan(0);

        var zoneId = await repo.CreateZoneAsync(admin, venueId, new CreateZoneRequest(s.ZoneCode, s.ZoneCode));
        zoneId.Should().BeGreaterThan(0);

        var seatId = await repo.CreateSeatAsync(admin, zoneId, new CreateSeatRequest(s.SeatCode, "IT-Seat"));
        seatId.Should().BeGreaterThan(0);
    }

    [Fact(DisplayName = "CreateVenue: Customer (không phải Admin) → SqlException 58101 (HTTP 403)")]
    public async Task CreateVenue_NonAdmin_Throws58101()
    {
        var s = NewSeeder();
        var customer = await s.CreateUserAsync("Customer");
        var repo = Repo();

        var act = () => repo.CreateVenueAsync(customer, new CreateVenueRequest(s.VenueName, "x"));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58101);
    }

    // ── Category + EventSeats ──────────────────────────────────────────────────

    [Fact(DisplayName = "ConfigureTicketCategory + AddEventSeats: thành công cho Organizer/Admin")]
    public async Task Category_And_AddEventSeats_Succeeds()
    {
        var (s, admin, _, venue, concertId) = await CreateDraftConcertAsync();
        var zone = await s.CreateZoneAsync(venue);
        var seat = await s.CreateSeatAsync(venue, zone);
        var repo = Repo();

        var catId = await repo.ConfigureTicketCategoryAsync(admin, concertId,
            new ConfigureTicketCategoryRequest(s.CategoryName, "desc"));
        catId.Should().BeGreaterThan(0);

        await repo.AddEventSeatsAsync(admin, concertId,
            new AddEventSeatsRequest(catId, 250000, new List<int> { seat }));

        var count = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM EventSeat WHERE ConcertID = @cid", new { cid = concertId });
        count.Should().Be(1);
    }
// ── Promotion + DiscountCode ───────────────────────────────────────────────

    [Fact(DisplayName = "CreatePromotion + CreateDiscountCode: thành công; ghi DB")]
    public async Task Promotion_And_DiscountCode_Succeeds()
    {
        var (s, admin, _, _, concertId) = await CreateDraftConcertAsync();
        var repo = Repo();

        var promoId = await repo.CreatePromotionAsync(admin, concertId,
            new CreatePromotionRequest(
                s.PromotionName, "desc", "FIXED", 10000,
                DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1),
                UsageLimit: 100, CodeRequiredFlag: true));
        promoId.Should().BeGreaterThan(0);

        var dcId = await repo.CreateDiscountCodeAsync(admin, promoId,
            new CreateDiscountCodeRequest(s.DiscountCodeValue));
        dcId.Should().BeGreaterThan(0);

        var exists = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM DiscountCode WHERE DiscountCodeID = @id", new { id = dcId });
        exists.Should().Be(1);
    }

    // ── AssignRole ─────────────────────────────────────────────────────────────

    [Fact(DisplayName = "AssignRole: Admin grant Organizer; không Admin → 58401")]
    public async Task AssignRole_AdminGrants_NonAdminDenied()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var target = await s.CreateUserAsync("Customer");
        var repo = Repo();

        await repo.AssignRoleAsync(admin, new AssignRoleRequest(target, "Organizer", "Grant"));

        var roles = await _fx.QueryAdminListAsync<string>(
            "SELECT r.RoleName FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID " +
            "WHERE ura.UserID = @uid AND ura.AssignmentStatus = 'Active'", new { uid = target });
        roles.Should().Contain("Organizer");

        var nonAdmin = await s.CreateUserAsync("Customer", instance: 2);
        var act = () => repo.AssignRoleAsync(nonAdmin, new AssignRoleRequest(target, "Admin", "Grant"));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58401);
    }

    // ── UpdateUserStatus ───────────────────────────────────────────────────────

    [Fact(DisplayName = "UpdateUserStatus: Admin disable; Customer → 58901")]
    public async Task UpdateUserStatus_AdminOnly()
    {
        var s = NewSeeder();
        var admin = await s.CreateUserAsync("Admin");
        var target = await s.CreateUserAsync("Customer");
        var repo = Repo();

        await repo.UpdateUserStatusAsync(admin, target, new UpdateUserStatusRequest("Disabled"));

        var status = await _fx.QueryAdminAsync<string>(
            "SELECT AccountStatus FROM UserAccount WHERE UserID = @id", new { id = target });
        status.Should().Be("Disabled");

        var customer = await s.CreateUserAsync("Customer", instance: 2);
        var act = () => repo.UpdateUserStatusAsync(customer, target, new UpdateUserStatusRequest("Disabled"));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58901);
    }

    // ── AddCheckinStaffAssignment ──────────────────────────────────────────────

    [Fact(DisplayName = "AddCheckinStaffAssignment: Admin assign staff; Customer → 59001")]
    public async Task AddCheckinStaffAssignment_AdminOnly()
    {
        var (s, admin, _, _, concertId) = await CreateDraftConcertAsync();
        var staff = await s.CreateUserAsync("Check-in Staff");
        var repo = Repo();

        await repo.AddCheckinStaffAssignmentAsync(admin,
            new AddCheckinStaffAssignmentRequest(staff, new List<int> { concertId }));

        var count = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM CheckinStaffAssignment WHERE UserID = @uid AND ConcertID = @cid",
            new { uid = staff, cid = concertId });
        count.Should().Be(1);

        var customer = await s.CreateUserAsync("Customer");
        var act = () => repo.AddCheckinStaffAssignmentAsync(customer,
            new AddCheckinStaffAssignmentRequest(staff, new List<int> { concertId }));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 59001);
    }
}
