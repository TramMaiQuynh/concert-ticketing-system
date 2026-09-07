namespace ConcertTicketing.Application.Services;

/// <summary>
/// Cấu hình cổng thanh toán đang dùng.
/// </summary>
/// <param name="IsSimulator">
/// true = dùng bộ mô phỏng cổng thanh toán chạy trong backend (chỉ cho demo/thử nghiệm;
/// Program.cs từ chối khởi động nếu bật ở môi trường Production).
/// </param>
/// <param name="PaymentUrlBase">
/// Địa chỉ người dùng được chuyển tới để hoàn tất thanh toán. Với chế độ mô phỏng, đây là
/// trang mô phỏng của frontend; với chế độ thật, đây là URL của PSP.
/// </param>
public sealed record PaymentGatewaySettings(bool IsSimulator, string PaymentUrlBase);
