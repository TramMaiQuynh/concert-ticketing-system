using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Data;
using System.Security.Claims;
using Dapper;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Application.Services;

namespace ConcertTicketing.API.Controllers;

/// <summary>
/// BỘ MÔ PHỎNG CỔNG THANH TOÁN — chỉ dùng cho demo/thử nghiệm.
///
/// VÌ SAO CẦN NÓ, VÀ VÌ SAO NÓ KHÔNG PHẢI LÀ "ĐI ĐƯỜNG TẮT":
///
/// Luồng thanh toán thật gồm ba bên: trình duyệt của khách, backend, và cổng thanh toán
/// (PSP). Backend tạo giao dịch rồi chuyển khách sang PSP; PSP thu tiền rồi gọi NGƯỢC về
/// webhook của backend theo kênh server-to-server, kèm chữ ký ký bằng bí mật dùng chung.
/// Trình duyệt không bao giờ chạm vào bí mật đó — nếu chạm được thì khách tự xác nhận
/// đơn của mình và nhận vé mà không trả tiền.
///
/// Hệ thống này chưa tích hợp PSP thật. Cách làm SAI mà một bản demo hay mắc phải là trả
/// chữ ký về cho trình duyệt để nó tự gọi webhook — đó chính là lỗ hổng đã tồn tại trong
/// bản frontend trước và đã bị gỡ bỏ.
///
/// Controller này thay vào đó đóng ĐÚNG VAI của PSP, nhưng chạy trong backend:
///   • bí mật chữ ký không rời khỏi máy chủ;
///   • nó TỰ TÍNH chữ ký rồi gọi vào cùng một <see cref="IPaymentRepository.ConfirmAsync"/>
///     mà PSP thật sẽ kích hoạt — nghĩa là bản demo vẫn chạy qua toàn bộ mã xác minh chữ
///     ký, xác minh số tiền, và mọi nhánh tự động hoàn tiền. Không có mã nào bị bỏ qua.
///
/// Ranh giới an toàn: Program.cs TỪ CHỐI khởi động nếu PaymentGateway:Mode = "Simulator"
/// trong môi trường Production, và mọi endpoint ở đây trả 404 khi không ở chế độ mô phỏng.
/// </summary>
[ApiController]
[Route("api/payment-simulator")]
[Authorize(Roles = "Customer")]
public class PaymentSimulatorController : ControllerBase
{
    private readonly IPaymentRepository _payments;
    private readonly IDbConnectionFactory _factory;
    private readonly PaymentGatewaySettings _gateway;
    private readonly string _signatureSecret;
    private readonly ILogger<PaymentSimulatorController> _logger;

    public PaymentSimulatorController(
        IPaymentRepository payments,
        IDbConnectionFactory factory,
        PaymentGatewaySettings gateway,
        IConfiguration configuration,
        ILogger<PaymentSimulatorController> logger)
    {
        _payments = payments;
        _factory = factory;
        _gateway = gateway;
        _signatureSecret = configuration["PaymentSignature:Secret"]!;
        _logger = logger;
    }

    /// <summary>Khách bấm "Thanh toán thành công" trên trang mô phỏng.</summary>
    [HttpPost("{bookingId:int}/{paymentId:int}/succeed")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Succeed(int bookingId, int paymentId)
    {
        if (!_gateway.IsSimulator) return NotFound();

        var amount = await GetOwnPaymentAmountAsync(bookingId, paymentId);
        if (amount is null) return NotFound();

        // Đóng vai PSP: chữ ký được tính ở phía máy chủ, đúng như cổng thật sẽ làm.
        var signature = PaymentSignatureCalculator.Compute(_signatureSecret, bookingId, paymentId, amount.Value);

        _logger.LogWarning(
            "MÔ PHỎNG CỔNG THANH TOÁN: xác nhận Payment {PaymentId} cho Booking {BookingId}. " +
            "Chế độ này chỉ dành cho demo, không có giao dịch tiền thật nào diễn ra.",
            paymentId, bookingId);

        var result = await _payments.ConfirmAsync(bookingId, paymentId, signature, $"SIMULATOR-{Guid.NewGuid():N}");

        return Ok(new
        {
            Outcome = result.Outcome.ToString(),
            result.BookingConfirmed,
            result.Message,
            Simulated = true,
        });
    }

    /// <summary>Khách bấm "Thanh toán thất bại" trên trang mô phỏng.</summary>
    [HttpPost("{bookingId:int}/{paymentId:int}/fail")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Fail(int bookingId, int paymentId)
    {
        if (!_gateway.IsSimulator) return NotFound();

        var amount = await GetOwnPaymentAmountAsync(bookingId, paymentId);
        if (amount is null) return NotFound();

        var signature = PaymentSignatureCalculator.Compute(_signatureSecret, bookingId, paymentId, amount.Value);

        _logger.LogWarning("MÔ PHỎNG CỔNG THANH TOÁN: đánh dấu thất bại Payment {PaymentId}.", paymentId);

        await _payments.FailAsync(bookingId, paymentId, signature, $"SIMULATOR-FAILED-{Guid.NewGuid():N}");

        return Ok(new { Message = "Giao dịch được đánh dấu thất bại.", Simulated = true });
    }

    /// <summary>
    /// Đọc số tiền của Payment, ĐỒNG THỜI kiểm tra Booking thuộc về người đang gọi.
    ///
    /// PSP thật không cần bước này (nó không biết người dùng là ai), nhưng bộ mô phỏng
    /// thì có: nếu bỏ qua, một khách có thể xác nhận thanh toán cho đơn của người khác.
    /// Ràng buộc quyền sở hữu ở đây chỉ chặt hơn luồng thật, không nới lỏng gì.
    /// </summary>
    private async Task<decimal?> GetOwnPaymentAmountAsync(int bookingId, int paymentId)
    {
        var userId = int.Parse(
            User.FindFirstValue(ClaimTypes.NameIdentifier)
            ?? throw new UnauthorizedAccessException("Token không hợp lệ."));

        using var conn = await _factory.OpenAsync();

        return await conn.QuerySingleOrDefaultAsync<decimal?>(@"
            SELECT p.Amount
            FROM   Payment p
            JOIN   Booking b ON b.BookingID = p.BookingID
            WHERE  p.PaymentID = @PaymentID
              AND  p.BookingID = @BookingID
              AND  b.CustomerUserID = @UserID;",
            new { PaymentID = paymentId, BookingID = bookingId, UserID = userId });
    }
}
