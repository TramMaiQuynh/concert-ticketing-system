using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho WaitlistRepository + QueueRepository (connection API thật):
/// - Waitlist: join thành công, QueuePosition ≥ 1, join lại → 58503, getMyEntry
/// - Concert không bật waitlist → 58502
/// - Queue: join thành công, join lại → 58703, getMyEntry
/// - Concert không bật fair access → 58702
/// </summary>
public sealed class WaitlistQueueRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public WaitlistQueueRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private WaitlistRepository WaitlistRepo() => new(_fx.ApiFactory);
    private QueueRepository QueueRepo() => new(_fx.ApiFactory);

    /// <summary>
    /// Tra ve Concert dang OnSale: sp_JoinQueue yeu cau Concert o giai doan mo ban
    /// (BP11), nen Concert Draft se bi tu choi bang 58704.
    /// </summary>
    private async Task<(int concertId, int customerId, int categoryId)> CreateConcertAsync(bool waitlist, bool fairAccess)
    {
        var s = NewSeeder();
        var organizer = await s.CreateUserAsync("Organizer");
        var customer = await s.CreateUserAsync("Customer");
        var artist = await s.CreateArtistAsync();
        var venue = await s.CreateVenueAsync();
        var concertId = await s.CreateConcertDraftAsync(organizer, artist, venue,
            waitlistEnabled: waitlist, fairAccess: fairAccess);
        var categoryId = await s.CreateTicketCategoryAsync(concertId);
        await s.SetConcertOnSaleAsync(concertId);
        return (concertId, customer, categoryId);
    }

    [Fact(DisplayName = "Waitlist: join → position ≥1; join lặp → 58503; getMyEntry trả đúng")]
    public async Task Waitlist_Join_ThenDuplicateRejected()
    {
        var (concertId, customer, categoryId) = await CreateConcertAsync(waitlist: true, fairAccess: false);
        var repo = WaitlistRepo();

        var join = await repo.JoinAsync(customer, concertId, categoryId, 1);
        join.WaitlistEntryId.Should().BeGreaterThan(0);
        join.QueuePosition.Should().BeGreaterThan(0);

        var entry = await repo.GetMyEntryAsync(customer, concertId);
        entry.Should().NotBeNull();
        entry!.WaitlistEntryId.Should().Be(join.WaitlistEntryId);
        entry.EntryStatus.Should().Be("Active");

        var act = () => repo.JoinAsync(customer, concertId, categoryId, 1);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58503);
    }

    [Fact(DisplayName = "Waitlist: concert không bật Waitlist → SqlException 58502")]
    public async Task Waitlist_ConcertDisabled_Throws58502()
    {
        var (concertId, customer, categoryId) = await CreateConcertAsync(waitlist: false, fairAccess: false);

        var act = () => WaitlistRepo().JoinAsync(customer, concertId, categoryId, 1);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58502);
    }

    [Fact(DisplayName = "Queue: join → QueueEntryId + Waiting; join lặp → 58703; getMyEntry")]
    public async Task Queue_Join_ThenDuplicateRejected()
    {
        var (concertId, customer, categoryId) = await CreateConcertAsync(waitlist: false, fairAccess: true);
        var repo = QueueRepo();

        var join = await repo.JoinAsync(customer, concertId);
        join.QueueEntryId.Should().BeGreaterThan(0);
        join.QueueStatus.Should().Be("Waiting");

        var entry = await repo.GetMyEntryAsync(customer, concertId);
        entry.Should().NotBeNull();
        entry!.QueueEntryId.Should().Be(join.QueueEntryId);

        var act = () => repo.JoinAsync(customer, concertId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58703);
    }

    [Fact(DisplayName = "Queue: concert không bật Fair Access → SqlException 58702")]
    public async Task Queue_ConcertDisabled_Throws58702()
    {
        var (concertId, customer, categoryId) = await CreateConcertAsync(waitlist: false, fairAccess: false);

        var act = () => QueueRepo().JoinAsync(customer, concertId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 58702);
    }

    /// <summary>
    /// Ghế được trả lại sau khi hết hạn giữ chỗ PHẢI đến được tay người đang xếp hàng chờ.
    ///
    /// Đây là test hồi quy cho một lỗi rò rỉ tồn kho có thật: sp_ReleaseExpiredHolds trả ghế
    /// về trạng thái OnHoldForWaitlist (đúng BR33a — ưu tiên hàng chờ trước khách vãng lai)
    /// nhưng KHÔNG tạo dòng phân bổ, trong khi sp_AllocateWaitlist trước đây chỉ tìm ghế
    /// 'Available'. Hệ quả: ghế trở nên vô hình với bộ cấp phát — khách trong hàng chờ không
    /// bao giờ được cấp cơ hội, và ghế cũng không bán được cho bất kỳ ai khác, vĩnh viễn.
    /// </summary>
    [Fact(DisplayName = "Waitlist: ghế hết hạn giữ chỗ phải được cấp cho người đang xếp hàng (chống rò rỉ tồn kho)")]
    public async Task Waitlist_SeatReleasedFromExpiredHold_IsGrantedToWaitingCustomer()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s, waitlistEnabled: true);

        // Khách A giữ TOÀN BỘ ghế của concert rồi bỏ ngang cho tới khi hết hạn.
        // Phải giữ hết: nếu còn bất kỳ ghế 'Available' nào thì bộ cấp phát sẽ lấy ghế đó
        // và che mất đúng lỗi cần kiểm tra (ghế vừa được trả lại có được nhìn thấy không).
        // Đây cũng là tình huống thật: chỉ khi cháy vé mới có người phải xếp hàng chờ.
        var booking = await new BookingRepository(_fx.ApiFactory).CreateAsync(
            baseline.CustomerUserId,
            new ConcertTicketing.Application.DTOs.CreateBookingRequest(
                baseline.ConcertId,
                new List<int> { baseline.EventSeatId1, baseline.EventSeatId2 }));

        var availableBefore = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM EventSeat WHERE ConcertID = @c AND InventoryStatus = 'Available';",
            new { c = baseline.ConcertId });
        availableBefore.Should().Be(0, "phải cháy vé thì kịch bản hàng chờ mới có nghĩa");

        // Đẩy CẢ hai mốc về quá khứ: CHK_Booking_HoldDates đòi Expiry > Start, nên chỉ
        // lùi riêng mốc hết hạn sẽ vi phạm ràng buộc thay vì tạo ra một hold đã hết hạn.
        await _fx.ExecAdminAsync(
            @"UPDATE Booking
              SET    HoldStartDatetime  = DATEADD(MINUTE, -20, SYSDATETIME()),
                     HoldExpiryDatetime = DATEADD(MINUTE,  -5, SYSDATETIME())
              WHERE  BookingID = @b;",
            new { b = booking.BookingId });

        // Khách B đang xếp hàng chờ đúng hạng vé đó.
        var waiting = await s.CreateUserAsync("Customer");
        await WaitlistRepo().JoinAsync(waiting, baseline.ConcertId, baseline.CategoryId, 1);

        // SIP1: giải phóng giữ chỗ hết hạn → ghế phải được dành riêng cho hàng chờ.
        await _fx.ExecAdminAsync("EXEC dbo.sp_ReleaseExpiredHolds @ConcertID = @c;",
            new { c = baseline.ConcertId });

        var seatStatus = await _fx.QueryAdminAsync<string>(
            "SELECT InventoryStatus FROM EventSeat WHERE EventSeatID = @es;",
            new { es = baseline.EventSeatId1 });
        seatStatus.Should().Be("OnHoldForWaitlist", "BR33a: ghế trả lại phải dành cho hàng chờ trước");

        // SIP2: bộ cấp phát phải NHÌN THẤY ghế đó và cấp cơ hội cho khách B.
        await _fx.ExecAdminAsync("EXEC dbo.sp_AllocateWaitlist @ConcertID = @c;",
            new { c = baseline.ConcertId });

        var entryStatus = await _fx.QueryAdminAsync<string>(
            "SELECT EntryStatus FROM WaitlistEntry WHERE WaitlistID = (SELECT WaitlistID FROM Waitlist WHERE ConcertID = @c) AND CustomerUserID = @u;",
            new { c = baseline.ConcertId, u = waiting });
        entryStatus.Should().Be("Granted",
            "ghế đã được trả lại thì người đang xếp hàng phải được cấp cơ hội, không được kẹt ở Active");

        var activeAllocations = await _fx.QueryAdminAsync<int>(
            @"SELECT COUNT(*) FROM WaitlistEntryEventSeatAllocation wea
              JOIN WaitlistEntry we ON we.WaitlistEntryID = wea.WaitlistEntryID
              WHERE we.CustomerUserID = @u AND wea.AllocationStatus = 'Active';",
            new { u = waiting });
        activeAllocations.Should().Be(1, "cơ hội được cấp phải gắn với đúng một ghế cụ thể");
    }
}