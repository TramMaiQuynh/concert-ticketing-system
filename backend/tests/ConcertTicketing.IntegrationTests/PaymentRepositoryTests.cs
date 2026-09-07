using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho PaymentRepository (connection API thật):
/// - ConfirmPayment: signature hợp lệ → thành công; sai signature → UnauthorizedAccessException; idempotent
/// - ProcessRefund: Admin → tạo Refund; customer (không quyền) → SqlException 53005
/// - Tiến trình Booking Pending → Confirm → Tickets Issued
/// </summary>
public sealed class PaymentRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public PaymentRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private BookingRepository BookingRepo() => new(_fx.ApiFactory);
    private PaymentRepository PaymentRepo() => new(_fx.ApiFactory, _fx.PaymentSignatureSecret, DbFixture.TestGateway);

    private async Task<(ConcertBaseline baseline, int bookingId, int paymentId, string signature)>
        CreateConfirmedPaymentAsync()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);

        await payment.ConfirmAsync(booking.BookingId, init.PaymentId, _fx.ComputePaymentSignature(booking.BookingId, init.PaymentId, init.Amount), "PROVIDER-REF");

        return (baseline, booking.BookingId, init.PaymentId, _fx.ComputePaymentSignature(booking.BookingId, init.PaymentId, init.Amount));
    }

    [Fact(DisplayName = "ConfirmPayment: signature hợp lệ → Payment Confirmed + Booking Confirmed + Ticket Issued")]
    public async Task ConfirmPayment_ValidSignature_ConfirmsAll()
    {
        var (_, bookingId, paymentId, _) = await CreateConfirmedPaymentAsync();

        var payStatus = await _fx.QueryAdminAsync<string>(
            "SELECT PaymentStatus FROM Payment WHERE PaymentID = @id", new { id = paymentId });
        payStatus.Should().Be("Confirmed");

        var bookStatus = await _fx.QueryAdminAsync<string>(
            "SELECT BookingStatus FROM Booking WHERE BookingID = @id", new { id = bookingId });
        bookStatus.Should().Be("Confirmed");

        var ticket = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Ticket WHERE BookingID = @bid AND TicketStatus = 'Issued'",
            new { bid = bookingId });
        ticket.Should().Be(1);
    }

    [Fact(DisplayName = "ConfirmPayment: signature sai → UnauthorizedAccessException (HTTP 401)")]
    public async Task ConfirmPayment_BadSignature_ThrowsUnauthorized()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));
        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);

        var act = () => payment.ConfirmAsync(booking.BookingId, init.PaymentId, "wrong-signature", "PROVIDER");
        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact(DisplayName = "ConfirmPayment: idempotent — confirm 2 lần đều không lỗi")]
    public async Task ConfirmPayment_Idempotent()
    {
        var (_, bookingId, paymentId, signature) = await CreateConfirmedPaymentAsync();

        // Lần 2: đã Confirmed → repo trả về sớm (idempotent)
        await PaymentRepo().ConfirmAsync(bookingId, paymentId, signature, "PROVIDER-2");
    }
[Fact(DisplayName = "ProcessRefund: Admin → tạo Refund; customer → SqlException 53005 (HTTP 403)")]
    public async Task ProcessRefund_AdminOk_CustomerDenied()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));
        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);
        await payment.ConfirmAsync(booking.BookingId, init.PaymentId, _fx.ComputePaymentSignature(booking.BookingId, init.PaymentId, init.Amount), "PROVIDER-REF");

        // Khach hang KHAC (khong so huu Booking) → 53011. Chinh chu thi DUOC tu huy (BR31),
        // nen phai dung mot user khac de kiem tra rang buoc quyen.
        var otherCustomer = await s.CreateUserAsync("Customer", instance: 9);
        var actNoPerm = () => payment.ProcessRefundAsync(booking.BookingId, "no", otherCustomer);
        await actNoPerm.Should().ThrowAsync<SqlException>().Where(e => e.Number == 53011);

        // Admin được phép — Refund tạo ra ở trạng thái Pending (BR22a), chờ ConfirmRefund
        var refundId = await payment.ProcessRefundAsync(booking.BookingId, "IT test", baseline.AdminUserId);
        refundId.Should().BeGreaterThan(0);

        var pending = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Refund WHERE RefundID = @id AND RefundStatus = 'Pending'",
            new { id = refundId });
        pending.Should().Be(1);
    }

    [Fact(DisplayName = "ConfirmRefund: Pending → Confirmed, Payment chuyển PartiallyRefunded/Refunded")]
    public async Task ConfirmRefund_UpdatesPaymentStatus()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));
        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);
        await payment.ConfirmAsync(booking.BookingId, init.PaymentId, _fx.ComputePaymentSignature(booking.BookingId, init.PaymentId, init.Amount), "PROVIDER-REF");

        var refundId = await payment.ProcessRefundAsync(booking.BookingId, "IT test", baseline.AdminUserId);
        await payment.ConfirmRefundAsync(refundId, baseline.AdminUserId);

        var confirmed = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Refund WHERE RefundID = @id AND RefundStatus = 'Confirmed'",
            new { id = refundId });
        confirmed.Should().Be(1);

        var payStatus = await _fx.QueryAdminAsync<string>(
            "SELECT PaymentStatus FROM Payment WHERE PaymentID = @id", new { id = init.PaymentId });
        payStatus.Should().BeOneOf("PartiallyRefunded", "Refunded");
    }

    [Fact(DisplayName = "ConfirmPayment: lệch số tiền → KHÔNG xác nhận Booking, tạo Refund, báo đúng Outcome")]
    public async Task ConfirmPayment_AmountMismatch_ReportsAutoRefund()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);

        // Mô phỏng cổng thanh toán gửi về số tiền khác tổng đơn hàng.
        // (Đường còn lại — áp khuyến mãi sau khi khởi tạo thanh toán — đã bị
        //  sp_ApplyPromotion chặn bằng 54013; đây là lớp bảo vệ thứ hai, độc lập.)
        await _fx.ExecAdminAsync(
            "UPDATE Booking SET FinalAmount = FinalAmount - 1 WHERE BookingID = @id",
            new { id = booking.BookingId });

        var result = await payment.ConfirmAsync(booking.BookingId, init.PaymentId,
            _fx.ComputePaymentSignature(booking.BookingId, init.PaymentId, init.Amount), "PROVIDER-REF");

        result.Outcome.Should().Be(PaymentConfirmOutcome.AutoRefundedAmountMismatch);
        result.BookingConfirmed.Should().BeFalse("đơn hàng không được xác nhận khi số tiền không khớp");

        // Sự thật tài chính vẫn được ghi nhận — KHÔNG bị ROLLBACK
        var payStatus = await _fx.QueryAdminAsync<string>(
            "SELECT PaymentStatus FROM Payment WHERE PaymentID = @id", new { id = init.PaymentId });
        payStatus.Should().Be("Confirmed");

        var effective = await _fx.QueryAdminAsync<bool>(
            "SELECT IsBookingConfirmingPayment FROM Payment WHERE PaymentID = @id", new { id = init.PaymentId });
        effective.Should().BeFalse("Payment lệch tiền không được giành quyền hiệu lực của Booking");

        var refunds = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Refund WHERE PaymentID = @id AND RefundStatus = 'Pending'",
            new { id = init.PaymentId });
        refunds.Should().Be(1, "phải tạo yêu cầu hoàn tiền cho khoản tiền đã thu");

        var tickets = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Ticket WHERE BookingID = @bid", new { bid = booking.BookingId });
        tickets.Should().Be(0);

        var bookStatus = await _fx.QueryAdminAsync<string>(
            "SELECT BookingStatus FROM Booking WHERE BookingID = @id", new { id = booking.BookingId });
        bookStatus.Should().Be("Pending", "Booking giữ nguyên Pending để khách trả lại đúng số tiền");
    }

    [Fact(DisplayName = "ApplyPromotion: đang có Payment Pending → SqlException 54013 (khóa giá)")]
    public async Task ApplyPromotion_WhilePaymentPending_Rejected()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        await PaymentRepo().InitiateAsync(booking.BookingId, baseline.CustomerUserId);

        var act = () => new BookingRepository(_fx.ApiFactory)
            .ApplyPromotionAsync(booking.BookingId, baseline.CustomerUserId, "KHONG-TON-TAI");

        // Mã không tồn tại nên dừng ở bước tra cứu; điều cần khẳng định là đường đi
        // KHÔNG bao giờ tới được sp_ApplyPromotion khi còn Payment Pending — kiểm tra
        // trực tiếp bằng SP để không phụ thuộc dữ liệu khuyến mãi của seeder.
        await act.Should().ThrowAsync<ArgumentException>();

        var ex = await Record.ExceptionAsync(() => _fx.ExecAdminAsync(@"
            DECLARE @pid INT, @out INT;
            EXEC sp_CreatePromotion @ActorUserID=@adm, @ConcertID=@cid, @PromotionName=N'IT Lock',
                 @PromotionDescription=N'd', @DiscountType='Fixed Amount', @DiscountValue=1000,
                 @StartDatetime=@ps, @EndDatetime=@pe, @UsageLimit=NULL, @CodeRequiredFlag=0,
                 @NewPromotionID=@pid OUTPUT;
            EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid, @DiscountCodeID=NULL, @ActorUserID=@cus;",
            new
            {
                adm = baseline.AdminUserId,
                cid = baseline.ConcertId,
                bid = booking.BookingId,
                cus = baseline.CustomerUserId,
                ps = DateTime.UtcNow.AddDays(-1),
                pe = DateTime.UtcNow.AddDays(10)
            }));

        ex.Should().BeOfType<SqlException>().Which.Number.Should().Be(54013);
    }

    [Fact(DisplayName = "ProcessRefund: Booking đã hủy → SqlException 53015 (HTTP 409)")]
    public async Task ProcessRefund_BookingNotCancellable_Throws53015()
    {
        var (baseline, bookingId, _, _) = await CreateConfirmedPaymentAsync();
        var payment = PaymentRepo();

        await payment.ProcessRefundAsync(bookingId, "first", baseline.AdminUserId);

        // Lần hai: Booking đã Cancelled → không còn hủy được
        var act = () => payment.ProcessRefundAsync(bookingId, "again", baseline.AdminUserId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 53015);
    }
}
