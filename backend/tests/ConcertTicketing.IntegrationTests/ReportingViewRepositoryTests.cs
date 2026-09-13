using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Hai nguồn đọc được nối dây muộn, cả hai đều dựa HOÀN TOÀN vào Row-Level Security
/// của view chứ không vào tham số truyền lên:
///   - VW_AuditTrail      (FR59/FR59a) — chỉ Admin.
///   - VW_WaitlistQueue   (BO11–BO12)  — Organizer sở hữu Concert, hoặc Admin.
///
/// Vì phạm vi do database quyết định, test phải đóng vai từng người dùng thật
/// (TestConnectionFactory.AsUser) thay vì tin vào [Authorize] ở tầng HTTP — nếu
/// thuộc tính đó bị gỡ nhầm, chính các bài dưới đây mới là thứ phát hiện ra.
/// </summary>
public sealed class ReportingViewRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;
    public ReportingViewRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private AdminRepository RepoAs(int userId) => new(_fx.ApiFactory.AsUser(userId));

    // ── VW_AuditTrail ────────────────────────────────────────────────────────

    [Fact(DisplayName = "AuditTrail: Admin đọc được nhật ký; Organizer/Customer/không danh tính → 0 dòng")]
    public async Task QueryAuditTrail_OnlyAdminSeesRows()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        // Sinh ra nhật ký thật bằng một thao tác nghiệp vụ thật (không chèn tay
        // vào AuditRecord — bảng đó bị TRG_AuditRecord_SecurityGuard canh giữ).
        var bookingRepo = new BookingRepository(_fx.ApiFactory);
        var booking = await bookingRepo.CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var asAdmin = await RepoAs(baseline.AdminUserId).QueryAuditTrailAsync(
            new AuditQueryRequest(EntityType: "Booking", EntityId: booking.BookingId.ToString()));
        asAdmin.Should().NotBeEmpty("Admin phải tra cứu được lịch sử của một entity (FR59a)");
        asAdmin.Should().OnlyContain(x => x.EntityType == "Booking"
                                       && x.EntityID == booking.BookingId.ToString());

        var asOrganizer = await RepoAs(baseline.OrganizerUserId).QueryAuditTrailAsync(new AuditQueryRequest());
        asOrganizer.Should().BeEmpty("Organizer không được đọc nhật ký kiểm toán");

        var asCustomer = await RepoAs(baseline.CustomerUserId).QueryAuditTrailAsync(new AuditQueryRequest());
        asCustomer.Should().BeEmpty("Customer không được đọc nhật ký kiểm toán");

        // Không có SESSION_CONTEXT = lời gọi không danh tính (webhook, worker nền).
        var anonymous = await new AdminRepository(_fx.ApiFactory).QueryAuditTrailAsync(new AuditQueryRequest());
        anonymous.Should().BeEmpty("không có danh tính thì phải fail-closed");
    }

    [Fact(DisplayName = "AuditTrail: số dòng trả về bị chặn trên phía máy chủ")]
    public async Task QueryAuditTrail_ServerEnforcesLimit()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var bookingRepo = new BookingRepository(_fx.ApiFactory);
        await bookingRepo.CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));
        await bookingRepo.CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId2 }));

        var repo = RepoAs(baseline.AdminUserId);

        (await repo.QueryAuditTrailAsync(new AuditQueryRequest(Limit: 1)))
            .Should().HaveCount(1, "Limit do người gọi yêu cầu phải được tôn trọng");

        // Người gọi đòi số dòng vô lý: máy chủ tự ép về trần, không được ném lỗi
        // và cũng không được trả về không giới hạn.
        (await repo.QueryAuditTrailAsync(new AuditQueryRequest(Limit: 100_000)))
            .Count().Should().BeLessThanOrEqualTo(500, "trần cứng phía máy chủ là 500");

        (await repo.QueryAuditTrailAsync(new AuditQueryRequest(Limit: 0)))
            .Should().NotBeEmpty("Limit không hợp lệ phải được ép về khoảng hợp lệ, không trả rỗng");
    }

    [Fact(DisplayName = "AuditTrail: lọc theo khoảng thời gian (FR56) dùng nửa mở [From, To)")]
    public async Task QueryAuditTrail_FiltersByTimeRange()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var before = DateTime.Now.AddMinutes(-1);

        await new BookingRepository(_fx.ApiFactory).CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var repo = RepoAs(baseline.AdminUserId);

        (await repo.QueryAuditTrailAsync(new AuditQueryRequest(From: before)))
            .Should().NotBeEmpty("sự kiện vừa sinh ra phải nằm trong khoảng đang mở");

        (await repo.QueryAuditTrailAsync(new AuditQueryRequest(To: before)))
            .Should().BeEmpty("không sự kiện nào xảy ra trước mốc đó trong bài test này");
    }

    // ── VW_WaitlistQueue ─────────────────────────────────────────────────────

    [Fact(DisplayName = "WaitlistQueue: Organizer sở hữu và Admin đọc được; Organizer khác → rỗng")]
    public async Task ListConcertWaitlist_ScopedToOwnerAndAdmin()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s, waitlistEnabled: true);

        var waitlistRepo = new WaitlistRepository(_fx.ApiFactory);
        var joined = await waitlistRepo.JoinAsync(
            baseline.CustomerUserId, baseline.ConcertId, baseline.CategoryId, requestedQuantity: 1);

        var asOwner = (await RepoAs(baseline.OrganizerUserId)
            .ListConcertWaitlistAsync(baseline.ConcertId)).ToList();
        asOwner.Should().ContainSingle(x => x.WaitlistEntryID == joined.WaitlistEntryId);
        asOwner[0].EntryStatus.Should().Be("Active");
        asOwner[0].RequestedQuantity.Should().Be(1);
        asOwner[0].CustomerUserID.Should().Be(baseline.CustomerUserId);

        var asAdmin = await RepoAs(baseline.AdminUserId).ListConcertWaitlistAsync(baseline.ConcertId);
        asAdmin.Should().ContainSingle(x => x.WaitlistEntryID == joined.WaitlistEntryId,
            "Admin nhìn được mọi Concert");

        var otherOrganizer = await s.CreateUserAsync("Organizer", instance: 7);
        var asStranger = await RepoAs(otherOrganizer).ListConcertWaitlistAsync(baseline.ConcertId);
        asStranger.Should().BeEmpty("Organizer khác không được nhìn danh sách chờ — view lộ tên khách (BR37)");

        var anonymous = await new AdminRepository(_fx.ApiFactory)
            .ListConcertWaitlistAsync(baseline.ConcertId);
        anonymous.Should().BeEmpty("không có danh tính thì phải fail-closed");
    }
}
