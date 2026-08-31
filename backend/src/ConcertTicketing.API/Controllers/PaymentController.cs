using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using Microsoft.Extensions.Logging;

namespace ConcertTicketing.API.Controllers;

[ApiController]
public class PaymentController : ControllerBase
{
    private readonly IPaymentRepository _paymentRepository;
    private readonly ILogger<PaymentController> _logger;

    public PaymentController(IPaymentRepository paymentRepository, ILogger<PaymentController> logger)
    {
        _paymentRepository = paymentRepository;
        _logger = logger;
    }

    [HttpPost("api/bookings/{bookingId:int}/payment")]
    [Authorize(Roles = "Customer")]
    public async Task<IActionResult> InitiatePayment(int bookingId, [FromBody] InitiatePaymentRequest request)
    {
        var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdString) || !int.TryParse(userIdString, out int userId))
            return Unauthorized();

        var response = await _paymentRepository.InitiateAsync(bookingId, userId);
        return Ok(response);
    }

    /// <summary>
    /// Callback webhook xác nhận thanh toán. Phải kèm <c>signature</c> (HMAC-SHA256)
    /// do backend tạo khi InitiatePayment; nếu không có chữ ký hợp lệ → 401.
    /// Idempotent: nếu Payment đã Confirmed → trả 200 mà không xử lý lại.
    /// </summary>
    [HttpPost("api/payments/confirm")]
    [AllowAnonymous] // Webhook callback — xác thực bằng chữ ký, không cần JWT
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> ConfirmPayment(
        [FromQuery] int bookingId,
        [FromQuery] int paymentId,
        [FromQuery] string? signature,
        [FromQuery] string? vnp_TransactionNo)
    {
        // Không nuốt exception — ErrorHandlingMiddleware map sang HTTP chuẩn.
        // UnauthorizedAccessException → 401 (chữ ký sai)
        // ArgumentException        → 400 (payment không tồn tại/sai booking)
        // SqlException (52001-52005) → 404/409/400 theo MapSqlException
        await _paymentRepository.ConfirmAsync(bookingId, paymentId, signature, vnp_TransactionNo);
        _logger.LogInformation("Payment {PaymentId} for Booking {BookingId} confirmed.", paymentId, bookingId);
        return Ok(new { Message = "Payment confirmed successfully." });
    }

    [HttpPost("api/payments/{paymentId:int}/refund")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> RefundPayment(int paymentId, [FromBody] RefundRequest request)
    {
        var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdString) || !int.TryParse(userIdString, out int userId))
            return Unauthorized();

        var newRefundId = await _paymentRepository.ProcessRefundAsync(paymentId, request.RefundAmount, request.Reason, userId);
        _logger.LogInformation("Refund {RefundId} for Payment {PaymentId} created by {Actor}.", newRefundId, paymentId, userId);
        return Ok(new { Message = "Refund processed successfully.", RefundId = newRefundId });
    }
}
