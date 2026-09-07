using System.Data;

namespace ConcertTicketing.Application.Interfaces;

/// <summary>
/// Mở kết nối tới database và thiết lập ngữ cảnh phiên (SESSION_CONTEXT) trước khi
/// bất kỳ câu lệnh nghiệp vụ nào chạy.
///
/// Vì sao cần: hệ thống dùng principal DUNG CHUNG (api_service) cho mọi request,
/// nên bản thân connection không nói được "ai đang thao tác". Bốn view Row-Level
/// Security (VW_CustomerBookingHistory, VW_OrganizerBooking/Payment/Ticket) và
/// TRG_AuditRecord_SecurityGuard đều đọc SESSION_CONTEXT(N'UserID') để biết điều đó.
/// Nếu không set, các view trả về 0 dòng (fail-closed) và trigger từ chối ghi Audit.
///
/// Mọi repository PHẢI lấy connection qua factory này thay vì tự new SqlConnection.
/// </summary>
public interface IDbConnectionFactory
{
    /// <summary>
    /// Mở connection và set SESSION_CONTEXT theo người dùng đang đăng nhập của request.
    /// Nếu request không có danh tính (webhook, background job), context không được set —
    /// các view RLS sẽ trả 0 dòng, đúng nguyên tắc fail-closed.
    /// </summary>
    Task<IDbConnection> OpenAsync(CancellationToken ct = default);

    /// <summary>
    /// Mở connection cho tiến trình nền chạy dưới danh nghĩa tài khoản hệ thống
    /// (SIP1–SIP5), nơi không có HTTP request nào để lấy danh tính.
    /// </summary>
    Task<IDbConnection> OpenForSystemAsync(CancellationToken ct = default);
}
