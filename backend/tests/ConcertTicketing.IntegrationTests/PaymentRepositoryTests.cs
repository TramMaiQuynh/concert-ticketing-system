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
    private BookingRepository BookingRepo() => new(_fx.ApiConnectionString);
    private PaymentRepository PaymentRepo() => new(_fx.ApiConnectionString, _fx.PaymentSignatureSecret);

    private async Task<(ConcertBaseline baseline, int bookingId, int paymentId, string signature)>
        CreateConfirmedPaymentAsync()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var booking = await BookingRepo().CreateAsync(baseline.CustomerUserId,
            new CreateBookingRequest(baseline.ConcertId, new List<int> { baseline.EventSeatId1 }));

        var payment = PaymentRepo();
        var init = await payment.InitiateAsync(booking.BookingId, baseline.CustomerUserId);

        await payment.ConfirmAsync(booking.BookingId, init.PaymentId, init.PaymentSignature, "PROVIDER-REF");

        return (baseline, booking.BookingId, init.PaymentId, init.PaymentSignature);
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
        await payment.ConfirmAsync(booking.BookingId, init.PaymentId, init.PaymentSignature, "PROVIDER-REF");

        // Organizer của concert hoặc Admin được phép
        var refundId = await payment.ProcessRefundAsync(init.PaymentId, 50000, "IT test", baseline.AdminUserId);
        refundId.Should().BeGreaterThan(0);

        var refund = await _fx.QueryAdminAsync<int>(
            "SELECT COUNT(*) FROM Refund WHERE RefundID = @id", new { id = refundId });
        refund.Should().Be(1);

        // Customer (không phải Admin/Organizer) → 53005
        var act = () => payment.ProcessRefundAsync(init.PaymentId, 10000, "no", baseline.CustomerUserId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 53005);
    }

    [Fact(DisplayName = "ProcessRefund: vượt tổng Refund > Payment.Amount → SqlException 53004 (HTTP 422)")]
    public async Task ProcessRefund_ExceedAmount_Throws53004()
    {
        var (baseline, _, paymentId, _) = await CreateConfirmedPaymentAsync();
        var payment = PaymentRepo();

        var act = () => payment.ProcessRefundAsync(paymentId, 999999, "too much", baseline.AdminUserId);
        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 53004);
    }
}
