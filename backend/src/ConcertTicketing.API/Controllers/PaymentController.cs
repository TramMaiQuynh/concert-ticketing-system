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
        // SqlException (52001, 52002, 52006) → 404/409 theo MapSqlException
        var result = await _paymentRepository.ConfirmAsync(bookingId, paymentId, signature, vnp_TransactionNo);

        // Vẫn trả 200 cho cổng thanh toán: webhook ĐÃ được xử lý thành công, cổng không
        // cần gửi lại. Nhưng KẾT QUẢ NGHIỆP VỤ phải nằm trong body — trước đây endpoint
        // này luôn trả "Payment confirmed successfully" kể cả khi đơn hàng không được
        // xác nhận và một yêu cầu hoàn tiền đã được tạo, tức là báo sai cho cả cổng
        // thanh toán lẫn client đang chờ kết quả.
        if (result.BookingConfirmed)
        {
            _logger.LogInformation(
                "Payment {PaymentId} for Booking {BookingId}: {Outcome}.",
                paymentId, bookingId, result.Outcome);
        }
        else
        {
            _logger.LogWarning(
                "Payment {PaymentId} for Booking {BookingId} KHONG xac nhan duoc don hang: {Outcome}. {Message}",
                paymentId, bookingId, result.Outcome, result.Message);
        }

        return Ok(new
        {
            Outcome = result.Outcome.ToString(),
            result.BookingConfirmed,
            result.Message
        });
    }

    /// <summary>
    /// Cổng thanh toán báo giao dịch thất bại. Bắt buộc phải có endpoint này:
    /// nếu thiếu, Payment kẹt ở Pending và khách không thể thanh toán lại
    /// cho tới khi hết hạn giữ chỗ (UIX_Payment_PendingPerBooking chặn).
    /// </summary>
    [HttpPost("api/payments/fail")]
    [AllowAnonymous] // Webhook callback — xác thực bằng chữ ký, không cần JWT
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> FailPayment(
        [FromQuery] int bookingId,
        [FromQuery] int paymentId,
        [FromQuery] string? signature,
        [FromQuery] string? vnp_TransactionNo)
    {
        await _paymentRepository.FailAsync(bookingId, paymentId, signature, vnp_TransactionNo);
        _logger.LogInformation("Payment {PaymentId} for Booking {BookingId} marked failed.", paymentId, bookingId);
        return Ok(new { Message = "Payment marked as failed." });
    }

    /// <summary>
    /// Hủy Booking đã xác nhận và tạo yêu cầu hoàn tiền (BP8 / BR31–BR34a).
    /// Số tiền hoàn do sp_ProcessRefund tự tính theo Concert.RefundPercentage —
    /// caller KHÔNG được chỉ định, để chính sách hoàn tiền không bị vượt mặt.
    /// Refund tạo ra ở trạng thái Pending, phải xác nhận qua endpoint confirm.
    /// </summary>
    [HttpPost("api/bookings/{bookingId:int}/refund")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> RefundBooking(int bookingId, [FromBody] RefundRequest? request = null)
    {
        var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdString) || !int.TryParse(userIdString, out int userId))
            return Unauthorized();

        var newRefundId = await _paymentRepository.ProcessRefundAsync(bookingId, request?.Reason, userId);

        // RefundId = 0 nghĩa là KHÔNG có khoản hoàn nào được tạo: Booking chưa thanh toán
        // nên hủy thẳng, hoặc chính sách Concert quy định tỷ lệ hoàn bằng 0. Phải nói đúng
        // như vậy thay vì luôn báo "đã tạo yêu cầu hoàn tiền".
        if (newRefundId == 0)
        {
            _logger.LogInformation("Booking {BookingId} cancelled by {Actor}; khong phat sinh hoan tien.", bookingId, userId);
            return Ok(new
            {
                Message = "Đã hủy Booking. Không phát sinh khoản hoàn tiền nào theo chính sách của Concert.",
                RefundId = (int?)null
            });
        }

        _logger.LogInformation("Refund {RefundId} for Booking {BookingId} created by {Actor}.", newRefundId, bookingId, userId);
        return Ok(new { Message = "Đã tạo yêu cầu hoàn tiền (Pending).", RefundId = newRefundId });
    }

    /// <summary>
    /// Khách tự hủy Booking của chính mình và yêu cầu hoàn tiền (BR18a / BR31).
    /// Không phải đặc quyền quản trị: sp_ProcessRefund vẫn tự áp hạn hủy (CI10) và
    /// tỷ lệ hoàn theo chính sách Concert (BR32a), nên khách không thể vượt chính sách.
    /// SP kiểm tra Booking có thuộc về người gọi hay không.
    /// </summary>
    [HttpPost("api/bookings/{bookingId:int}/cancel")]
    [Authorize(Roles = "Customer")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> CancelOwnBooking(int bookingId, [FromBody] RefundRequest? request = null)
    {
        var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdString) || !int.TryParse(userIdString, out int userId))
            return Unauthorized();

        var refundId = await _paymentRepository.ProcessRefundAsync(bookingId, request?.Reason, userId);
        _logger.LogInformation("Booking {BookingId} cancelled by owner {UserId}, refund {RefundId}.",
            bookingId, userId, refundId);

        return Ok(refundId == 0
            ? new { Message = "Đã hủy Booking. Không phát sinh khoản hoàn tiền nào theo chính sách của Concert.", RefundId = (int?)null }
            : new { Message = "Đã hủy Booking và tạo yêu cầu hoàn tiền (Pending).", RefundId = (int?)refundId });
    }

    /// <summary>Xác nhận hoàn tiền đã thực hiện xong ở cổng thanh toán (BR32b).</summary>
    [HttpPost("api/refunds/{refundId:int}/confirm")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> ConfirmRefund(int refundId)
    {
        var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdString) || !int.TryParse(userIdString, out int userId))
            return Unauthorized();

        await _paymentRepository.ConfirmRefundAsync(refundId, userId);
        _logger.LogInformation("Refund {RefundId} confirmed by {Actor}.", refundId, userId);
        return Ok(new { Message = "Refund confirmed." });
    }

    /// <summary>
    /// Kết thúc một yêu cầu hoàn tiền MÀ KHÔNG chi trả: Pending → Failed | Cancelled.
    ///
    /// Đây là đường đi còn thiếu của vòng đời Refund. Trước khi có nó, một khoản hoàn
    /// bị cổng thanh toán từ chối không có cách nào đóng lại — nó nằm Pending vĩnh
    /// viễn và không gì phân biệt được "đang chờ settle" với "đã thất bại".
    ///
    /// KHÔNG đụng tới Payment: không đồng nào rời tài khoản thu.
    /// </summary>
    [HttpPut("api/refunds/{refundId:int}/status")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateRefundStatus(int refundId, [FromBody] UpdateRefundStatusRequest request)
    {
        var userIdString = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userIdString) || !int.TryParse(userIdString, out int userId))
            return Unauthorized();

        await _paymentRepository.UpdateRefundStatusAsync(refundId, userId, request.Status, request.Reason);
        _logger.LogInformation("Refund {RefundId} closed as {Status} by {Actor}.", refundId, request.Status, userId);
        return NoContent();
    }
}
