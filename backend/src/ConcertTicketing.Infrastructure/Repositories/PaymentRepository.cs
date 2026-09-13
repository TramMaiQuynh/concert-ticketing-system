using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Application.Services;

namespace ConcertTicketing.Infrastructure.Repositories;

public class PaymentRepository : IPaymentRepository
{
    private readonly IDbConnectionFactory _factory;
    private readonly string _signatureSecret;
    private readonly PaymentGatewaySettings _gateway;

    public PaymentRepository(IDbConnectionFactory factory, string signatureSecret,
                             PaymentGatewaySettings gateway)
    {
        _factory = factory;
        _signatureSecret = signatureSecret;
        _gateway = gateway;
    }

    public async Task<InitiatePaymentResponse> InitiateAsync(int bookingId, int customerUserId)
    {
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        p.Add("@BookingID", bookingId, DbType.Int32);
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);
        p.Add("@NewPaymentID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        // @PaymentReference la ma tham chieu noi bo, thuan ASCII; SP khai bao VARCHAR(64).
        p.Add("@PaymentReference", dbType: DbType.AnsiString, size: 64, direction: ParameterDirection.Output);
        p.Add("@Amount", dbType: DbType.Decimal, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_InitiatePayment", p, commandType: CommandType.StoredProcedure);

        var paymentId = p.Get<int>("@NewPaymentID");
        var paymentReference = p.Get<string>("@PaymentReference");
        var amount = p.Get<decimal>("@Amount");

        // Chu ky KHONG duoc tra ve cho client - xem PaymentSignatureCalculator.
        // No la bi mat dung chung backend<->cong thanh toan, chuyen giao server-to-server.
        //
        // Dia chi cong thanh toan lay tu cau hinh thay vi viet cung URL sandbox cua VNPay:
        // moi trien khai (demo dung bo mo phong, that dung PSP that) tro toi mot noi khac
        // nhau, va viet cung nghia la khong the doi ma khong sua ma nguon.
        var paymentUrl = _gateway.IsSimulator
            ? $"{_gateway.PaymentUrlBase}/{bookingId}/{paymentId}"
            : $"{_gateway.PaymentUrlBase}?paymentId={paymentId}&vnp_TxnRef={paymentReference}";

        return new InitiatePaymentResponse(paymentId, paymentUrl, paymentReference, amount);
    }

    /// <summary>
    /// Xử lý callback xác nhận thanh toán từ cổng thanh toán.
    ///
    /// Trả về KẾT QUẢ NGHIỆP VỤ chứ không chỉ "thành công/thất bại": sp_ConfirmPayment
    /// commit thành công cả trong những tình huống bất thường (lệch số tiền, Booking hết
    /// hạn, Booking đã có Payment hiệu lực khác) — khi đó nó ghi nhận tiền đã thu rồi tạo
    /// yêu cầu hoàn tiền, và Booking KHÔNG được xác nhận. Caller bắt buộc phải phân biệt
    /// được hai trường hợp này.
    /// </summary>
    public async Task<ConfirmPaymentResult> ConfirmAsync(int bookingId, int paymentId, string? signature, string? providerReference)
    {
        using var conn = await _factory.OpenAsync();

        // Xác thực chữ ký (callback phải trình chữ ký hợp lệ)
        var amount = await GetPaymentAmountAsync(conn, bookingId, paymentId);
        if (amount is null)
            throw new ArgumentException("Payment không tồn tại hoặc không thuộc Booking.");

        if (!PaymentSignatureCalculator.Verify(_signatureSecret, bookingId, paymentId, amount.Value, signature))
            throw new UnauthorizedAccessException("Chữ ký thanh toán không hợp lệ.");

        // KHÔNG kiểm tra idempotency ở đây nữa: sp_ConfirmPayment đã có kiểm tra đó
        // dưới applock theo Booking và phân biệt được "đã xác nhận" với "đã bị hoàn".
        // Kiểm tra trùng lặp ở tầng này chỉ tạo thêm một nguồn quyết định thứ hai —
        // không có khóa, đọc trước khi SP chạy — và trước đây nó trả về "thành công"
        // cho cả Payment đã bị tự động hoàn tiền.
        var p = new DynamicParameters();
        p.Add("@BookingID", bookingId, DbType.Int32);
        p.Add("@PaymentID", paymentId, DbType.Int32);
        // DbType.AnsiString: @ProviderReference la du lieu tu cong thanh toan ben ngoai,
        // va SP khai bao VARCHAR(64) (khong Unicode) - khop dung kieu de tranh ep kieu ngam.
        p.Add("@ProviderReference", providerReference, DbType.AnsiString, size: 64);
        // @Outcome la ma ket qua thuan ASCII ("Confirmed", "AutoRefunded_..."); SP khai bao VARCHAR(48).
        p.Add("@Outcome", dbType: DbType.AnsiString, size: 48, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_ConfirmPayment", p, commandType: CommandType.StoredProcedure);

        return MapOutcome(p.Get<string?>("@Outcome"));
    }

    private static ConfirmPaymentResult MapOutcome(string? raw) => raw switch
    {
        "Confirmed" => new(PaymentConfirmOutcome.Confirmed, true,
            "Thanh toán đã được xác nhận, vé đã phát hành."),
        "AlreadyConfirmed" => new(PaymentConfirmOutcome.AlreadyConfirmed, true,
            "Giao dịch đã được xác nhận trước đó."),
        "AlreadyRefunded" => new(PaymentConfirmOutcome.AlreadyRefunded, false,
            "Giao dịch đã được ghi nhận nhưng trước đó đã có yêu cầu hoàn tiền; đơn hàng không được xác nhận."),
        "AutoRefunded_AmountMismatch" => new(PaymentConfirmOutcome.AutoRefundedAmountMismatch, false,
            "Số tiền thanh toán không khớp tổng đơn hàng. Tiền đã thu được ghi nhận và một yêu cầu hoàn tiền đã được tạo."),
        "AutoRefunded_DuplicatePayment" => new(PaymentConfirmOutcome.AutoRefundedDuplicatePayment, false,
            "Đơn hàng đã có giao dịch thanh toán hiệu lực khác. Một yêu cầu hoàn tiền đã được tạo."),
        "AutoRefunded_BookingNotPending" => new(PaymentConfirmOutcome.AutoRefundedBookingNotPending, false,
            "Đơn hàng đã hết hạn giữ chỗ hoặc không còn chờ thanh toán. Một yêu cầu hoàn tiền đã được tạo."),
        // sp_ConfirmPayment đặt @Outcome trên MỌI nhánh thoát; null nghĩa là SP đã bị
        // thay đổi mà không cập nhật chỗ này — phải nổ chứ không được đoán là thành công.
        _ => throw new InvalidOperationException(
            $"sp_ConfirmPayment trả về @Outcome không nhận diện được: '{raw ?? "(null)"}'.")
    };

    /// <summary>
    /// Hủy Booking đã Confirmed và tạo yêu cầu hoàn tiền (BP8 / BR31–BR34a).
    /// Giá trị hoàn KHÔNG do caller quyết định: sp_ProcessRefund tự tính theo
    /// Concert.RefundPercentage và kiểm tra hạn hủy theo CancellationDeadlineHours.
    /// Refund được tạo ở trạng thái Pending, phải gọi ConfirmRefundAsync để hoàn tất.
    /// </summary>
    public async Task<int> ProcessRefundAsync(int bookingId, string? reason, int actorUserId,
                                              bool isConcertCancellation = false)
    {
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        p.Add("@BookingID", bookingId, DbType.Int32);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@RefundReason", reason, DbType.String, size: 500);
        p.Add("@IsConcertCancellation", isConcertCancellation, DbType.Boolean);
        p.Add("@NewRefundID", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_ProcessRefund", p, commandType: CommandType.StoredProcedure);

        // Lấy thẳng ID do SP trả về. Trước đây chỗ này truy vấn "Refund mới nhất của
        // Booking" để đoán — sai trong đúng những trường hợp quan trọng: hủy một Booking
        // đang Pending không tạo Refund nào, và Concert có RefundPercentage = 0 cũng vậy;
        // khi đó truy vấn kia trả về một Refund CŨ không liên quan (ví dụ khoản tự động
        // hoàn tiền do lệch số tiền trước đó), khiến caller tưởng vừa tạo được yêu cầu
        // hoàn tiền và có thể đem chính ID đó đi gọi ConfirmRefundAsync.
        // 0 = lần gọi này không tạo Refund nào (hủy Booking chưa thanh toán, hoặc tỷ lệ hoàn = 0).
        return p.Get<int?>("@NewRefundID") ?? 0;
    }

    /// <summary>Xác nhận một Refund đang Pending (BP8 / BR32b) — chỉ Admin/Organizer.</summary>
    public async Task ConfirmRefundAsync(int refundId, int actorUserId)
    {
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        p.Add("@RefundID", refundId, DbType.Int32);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);

        await conn.ExecuteAsync("sp_ConfirmRefund", p, commandType: CommandType.StoredProcedure);
    }

    /// <summary>
    /// Kết thúc một yêu cầu hoàn tiền mà không chi trả (Pending → Failed | Cancelled).
    /// KHÔNG đụng tới Payment.PaymentStatus: không đồng nào rời tài khoản thu, nên
    /// việc chuyển Payment sang PartiallyRefunded/Refunded vẫn là độc quyền của
    /// sp_ConfirmRefund (BR32b).
    /// </summary>
    public async Task UpdateRefundStatusAsync(int refundId, int actorUserId, string newStatus, string reason)
    {
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@RefundID", refundId, DbType.Int32);
        // size khớp đúng độ rộng tham số của SP: VARCHAR(32) và NVARCHAR(500).
        p.Add("@NewStatus", newStatus, DbType.AnsiString, size: 32);
        p.Add("@Reason", reason, DbType.String, size: 500);

        await conn.ExecuteAsync("sp_UpdateRefundStatus", p, commandType: CommandType.StoredProcedure);
    }

    /// <summary>
    /// Ghi nhận thanh toán thất bại từ cổng thanh toán (BP6 / BR24).
    /// Bắt buộc phải có: nếu thiếu, Payment kẹt ở Pending và
    /// UIX_Payment_PendingPerBooking sẽ chặn mọi lần thanh toán lại.
    /// </summary>
    public async Task FailAsync(int bookingId, int paymentId, string? signature, string? providerReference)
    {
        using var conn = await _factory.OpenAsync();

        var amount = await GetPaymentAmountAsync(conn, bookingId, paymentId);
        if (amount is null)
            throw new ArgumentException("Payment không tồn tại hoặc không thuộc Booking.");

        if (!PaymentSignatureCalculator.Verify(_signatureSecret, bookingId, paymentId, amount.Value, signature))
            throw new UnauthorizedAccessException("Chữ ký thanh toán không hợp lệ.");

        var p = new DynamicParameters();
        p.Add("@PaymentID", paymentId, DbType.Int32);
        // DbType.AnsiString: @ProviderReference la du lieu tu cong thanh toan ben ngoai,
        // va SP khai bao VARCHAR(64) (khong Unicode) - khop dung kieu de tranh ep kieu ngam.
        p.Add("@ProviderReference", providerReference, DbType.AnsiString, size: 64);

        await conn.ExecuteAsync("sp_FailPayment", p, commandType: CommandType.StoredProcedure);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private static async Task<decimal?> GetPaymentAmountAsync(IDbConnection conn, int bookingId, int paymentId)
        => await conn.QuerySingleOrDefaultAsync<decimal?>(
            "SELECT Amount FROM Payment WHERE PaymentID = @PaymentID AND BookingID = @BookingID",
            new { PaymentID = paymentId, BookingID = bookingId });

    private static async Task<string?> GetPaymentStatusAsync(IDbConnection conn, int bookingId, int paymentId)
        => await conn.QuerySingleOrDefaultAsync<string?>(
            "SELECT PaymentStatus FROM Payment WHERE PaymentID = @PaymentID AND BookingID = @BookingID",
            new { PaymentID = paymentId, BookingID = bookingId });
}