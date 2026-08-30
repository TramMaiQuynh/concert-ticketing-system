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

        try
        {
            var response = await _paymentRepository.InitiateAsync(bookingId, userId);
            return Ok(response);
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new { Message = ex.Message });
        }
    }

    [HttpPost("api/payments/confirm")]
    [AllowAnonymous] // Usually webhooks don't use JWT, they use signature verification (skipped here for simplicity)
    public async Task<IActionResult> ConfirmPayment([FromQuery] int bookingId, [FromQuery] int paymentId, [FromQuery] string? vnp_TransactionNo)
    {
        try
        {
            await _paymentRepository.ConfirmAsync(bookingId, paymentId, vnp_TransactionNo);
            _logger.LogInformation("Payment {PaymentId} for Booking {BookingId} confirmed.", paymentId, bookingId);
            return Ok(new { Message = "Payment confirmed successfully." });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to confirm payment {PaymentId}.", paymentId);
            return BadRequest(new { Message = "Failed to confirm payment." });
        }
    }

    [HttpPost("api/payments/{paymentId:int}/refund")]
    [Authorize(Roles = "Admin,Organizer")]
    public async Task<IActionResult> RefundPayment(int paymentId, [FromBody] RefundRequest request)
    {
        var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdString) || !int.TryParse(userIdString, out int userId))
            return Unauthorized();

        try
        {
            var newRefundId = await _paymentRepository.ProcessRefundAsync(paymentId, request.RefundAmount, request.Reason, userId);
            return Ok(new { Message = "Refund processed successfully.", RefundId = newRefundId });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to process refund for payment {PaymentId}.", paymentId);
            return BadRequest(new { Message = "Failed to process refund. " + ex.Message });
        }
    }
}
