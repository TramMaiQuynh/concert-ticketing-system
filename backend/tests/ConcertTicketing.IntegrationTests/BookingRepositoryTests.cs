using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho BookingRepository + Repository initiate-payment (chạy với connection API thật):
/// - CreateBooking thành công / giữ ghế / subtotal
/// - Không OnSale → 51001; vượt purchase limit → 51003; ghế đã giữ → 51004
/// - ApplyPromotion hợp lệ; mã sai → ArgumentException; promotion hết hạn → 54006
/// - CancelBooking thành công; cancel lại → 55002; cancel booking của user khác → 55001
/// - InitiatePayment thành công; gọi lại → 56003 (409)
/// </summary>
public sealed class BookingRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public BookingRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private BookingRepository Repo() => new(_fx.ApiConnectionString);
    private PaymentRepository PaymentRepo() => new(_fx.ApiConnectionString, _fx.PaymentSignatureSecret);

    // ── CreateBooking ──────────────────────────────────────────────────────────

    [Fact(DisplayName = "CreateBooking: thành công, trả BookingID + Reference + Pending; EventSeat sang OnHold")]
    public async Task CreateBooking_Success()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var repo = Repo();

        var resp = await repo.CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        resp.BookingId.Should().BeGreaterThan(0);
        resp.BookingReference.Should().NotBeNullOrEmpty();
        resp.Status.Should().Be("Pending");
        resp.FinalAmount.Should().Be(100000);

        var seatStatus = await _fx.QueryAdminAsync<string>(
            "SELECT InventoryStatus FROM EventSeat WHERE EventSeatID = @id", new { id = baseline.EventSeatId1 });
        seatStatus.Should().Be("OnHold");

        var count = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM BookingEventSeatAllocation WHERE BookingID = @bid",
            new { bid = resp.BookingId });
        count.Should().Be(1);
    }

    [Fact(DisplayName = "CreateBooking: concert chưa OnSale → SqlException 51001 (HTTP 400)")]
    public async Task CreateBooking_ConcertNotOnSale_Throws51001()
    {
        var s = NewSeeder();
        var organizer = await s.CreateUserAsync("Organizer");
        var customer = await s.CreateUserAsync("Customer");
        var artist = await s.CreateArtistAsync();
        var venue = await s.CreateVenueAsync();
        var zone = await s.CreateZoneAsync(venue);
        var seat = await s.CreateSeatAsync(venue, zone);
        // Concert vẫn ở Draft — KHÔNG SetOnSale
        var concertId = await s.CreateConcertDraftAsync(organizer, artist, venue);
        var category = await s.CreateTicketCategoryAsync(concertId);
        var eventSeat = await s.CreateEventSeatAsync(concertId, seat, category);

        var act = () => Repo().CreateAsync(customer,
            new CreateBookingRequest(concertId, new List<int> { eventSeat }));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 51001);
    }

    [Fact(DisplayName = "CreateBooking: vượt PurchaseLimit (limit=1, đặt 2 ghế) → SqlException 51003")]
    public async Task CreateBooking_OverPurchaseLimit_Throws51003()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s, purchaseLimit: 1);

        var act = () => Repo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId,
                new List<int> { baseline.EventSeatId1, baseline.EventSeatId2 }));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 51003);
    }

    [Fact(DisplayName = "CreateBooking: ghế đã bị giữ (OnHold) → SqlException 51004 (HTTP 400)")]
    public async Task CreateBooking_SeatAlreadyHeld_Throws51004()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var repo = Repo();

        var first = await repo.CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));
        first.Status.Should().Be("Pending");

        // Booking lần 2 với cùng ghế — đã OnHold (bởi booking của chính user này)
        var act = () => repo.CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 51004);
    }
[Fact(DisplayName = "ApplyPromotion: mã hợp lệ giảm FinalAmount")]
    public async Task ApplyPromotion_ValidCode_DiscountsBooking()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var adminRepo = new AdminRepository(_fx.ApiConnectionString);

        var promoId = await adminRepo.CreatePromotionAsync(baseline.AdminUserId, baseline.ConcertId,
            new CreatePromotionRequest(
                s.PromotionName + "-B", "desc", "FIXED", 20000,
                DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1),
                UsageLimit: 100, CodeRequiredFlag: true));
        var code = "BOOK-" + s.DiscountCodeValue;
        await adminRepo.CreateDiscountCodeAsync(baseline.AdminUserId, promoId,
            new CreateDiscountCodeRequest(code));

        var booking = await Repo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        await Repo().ApplyPromotionAsync(booking.BookingId, baseline.CustomerUserId, code);

        var final = await _fx.QueryAdminAsync<decimal>(
            "SELECT FinalAmount FROM Booking WHERE BookingID = @id", new { id = booking.BookingId });
        final.Should().Be(80000);

        var apps = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM BookingPromotionApplication WHERE BookingID = @id",
            new { id = booking.BookingId });
        apps.Should().Be(1);
    }

    [Fact(DisplayName = "ApplyPromotion: mã không tồn tại → ArgumentException (HTTP 400)")]
    public async Task ApplyPromotion_InvalidCode_Throws()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await Repo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var act = () => Repo().ApplyPromotionAsync(booking.BookingId, baseline.CustomerUserId, "WRONG-CODE");
        await act.Should().ThrowAsync<ArgumentException>();
    }

    [Fact(DisplayName = "ApplyPromotion: promotion hết hiệu lực → SqlException 54006 (HTTP 400)")]
    public async Task ApplyPromotion_Expired_Throws54006()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var adminRepo = new AdminRepository(_fx.ApiConnectionString);

        var promoId = await adminRepo.CreatePromotionAsync(baseline.AdminUserId, baseline.ConcertId,
            new CreatePromotionRequest(
                s.PromotionName + "-Exp", "desc", "FIXED", 5000,
                DateTime.UtcNow.AddDays(-5), DateTime.UtcNow.AddDays(-2),
                UsageLimit: 100, CodeRequiredFlag: false));
        var code = "EXPC-" + s.DiscountCodeValue;
        await adminRepo.CreateDiscountCodeAsync(baseline.AdminUserId, promoId,
            new CreateDiscountCodeRequest(code,
                ValidFromDatetime: DateTime.UtcNow.AddDays(-5),
                ValidToDatetime: DateTime.UtcNow.AddDays(-2)));

        var booking = await Repo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var act = () => Repo().ApplyPromotionAsync(booking.BookingId, baseline.CustomerUserId, code);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 54006);
    }
// ── CancelBooking ──────────────────────────────────────────────────────────

    [Fact(DisplayName = "CancelBooking: hủy thành công → Cancelled + EventSeat Available; hủy lại → 55002")]
    public async Task CancelBooking_Success_Then_SecondCancelRejected()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await Repo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        await Repo().CancelAsync(booking.BookingId, baseline.CustomerUserId);

        var status = await _fx.QueryAdminAsync<string>(
            "SELECT BookingStatus FROM Booking WHERE BookingID = @id", new { id = booking.BookingId });
        status.Should().Be("Cancelled");

        var seatStatus = await _fx.QueryAdminAsync<string>(
            "SELECT InventoryStatus FROM EventSeat WHERE EventSeatID = @id", new { id = baseline.EventSeatId1 });
        seatStatus.Should().Be("Available");

        var act = () => Repo().CancelAsync(booking.BookingId, baseline.CustomerUserId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 55002);
    }

    [Fact(DisplayName = "CancelBooking: booking không thuộc user → SqlException 55001")]
    public async Task CancelBooking_NotOwned_Throws55001()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var other = await s.CreateUserAsync("Customer", instance: 2);
        var booking = await Repo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var act = () => Repo().CancelAsync(booking.BookingId, other);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 55001);
    }

    // ── InitiatePayment (repository tương tác SP) ─────────────────────────────

    [Fact(DisplayName = "InitiatePayment: thành công (Pending); gọi lại → SqlException 56003 (409)")]
    public async Task InitiatePayment_Success_ThenDuplicateRejected()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await Repo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);
        init.PaymentId.Should().BeGreaterThan(0);
        init.PaymentReference.Should().NotBeNullOrEmpty();
        init.Amount.Should().Be(100000);
        init.PaymentSignature.Should().NotBeNullOrEmpty();

        var status = await _fx.QueryAdminAsync<string>(
            "SELECT PaymentStatus FROM Payment WHERE PaymentID = @id", new { id = init.PaymentId });
        status.Should().Be("Pending");

        var act = () => payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 56003);
    }
}
