using System.Security.Cryptography;
using System.Text;

namespace ConcertTicketing.Application.Services;

/// <summary>
/// Tính chữ ký HMAC-SHA256 cho callback thanh toán.
///
/// MÔ HÌNH TIN CẬY: bí mật ký (<c>PaymentSignature:Secret</c>) được chia sẻ giữa
/// BACKEND và CỔNG THANH TOÁN — KHÔNG BAO GIỜ được gửi cho client, và chữ ký
/// tính từ nó cũng vậy. Callback xác nhận/thất bại chỉ được chấp nhận khi bên gọi
/// trình được chữ ký hợp lệ, tức bên gọi phải biết bí mật.
///
/// Vì sao điều này quan trọng: nếu chữ ký được trả về cho client trong response
/// của bước khởi tạo thanh toán, thì chính khách hàng có thể gọi thẳng endpoint
/// xác nhận và nhận vé mà không trả tiền. Đó là lý do
/// <see cref="ConcertTicketing.Application.DTOs.InitiatePaymentResponse"/>
/// KHÔNG chứa trường chữ ký.
/// </summary>
public static class PaymentSignatureCalculator
{
    /// <summary>
    /// Payload được ký: <c>bookingId:paymentId:amount</c>. Ràng buộc cả ba giá trị
    /// vào một chữ ký để không thể dùng lại chữ ký của giao dịch này cho giao dịch khác.
    /// </summary>
    public static string Compute(string secret, int bookingId, int paymentId, decimal amount)
    {
        var payload = $"{bookingId}:{paymentId}:{amount.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)}";
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(secret));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }

    /// <summary>So sánh chữ ký theo thời gian hằng số để không rò rỉ thông tin qua timing.</summary>
    public static bool Verify(string secret, int bookingId, int paymentId, decimal amount, string? presented)
    {
        if (string.IsNullOrEmpty(presented)) return false;
        var expected = Compute(secret, bookingId, paymentId, amount);
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(presented),
            Encoding.UTF8.GetBytes(expected));
    }
}
