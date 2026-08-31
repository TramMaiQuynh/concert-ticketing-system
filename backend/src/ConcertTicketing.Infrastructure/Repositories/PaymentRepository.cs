using System.Data;
using System.Security.Cryptography;
using System.Text;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class PaymentRepository : IPaymentRepository
{
    private readonly string _connectionString;
    private readonly string _signatureSecret;

    public PaymentRepository(string connectionString, string signatureSecret)
    {
        _connectionString = connectionString;
        _signatureSecret = signatureSecret;
    }

    public async Task<InitiatePaymentResponse> InitiateAsync(int bookingId, int customerUserId)
    {
        using var conn = new SqlConnection(_connectionString);

        var p = new DynamicParameters();
        p.Add("@BookingID", bookingId, DbType.Int32);
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);
        p.Add("@NewPaymentID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        p.Add("@PaymentReference", dbType: DbType.String, size: 64, direction: ParameterDirection.Output);
        p.Add("@Amount", dbType: DbType.Decimal, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_InitiatePayment", p, commandType: CommandType.StoredProcedure);

        var paymentId = p.Get<int>("@NewPaymentID");
        var paymentReference = p.Get<string>("@PaymentReference");
        var amount = p.Get<decimal>("@Amount");

        // Chữ ký: HMAC-SHA256(secret, bookingId:paymentId:amount) — ngăn tự confirm
        var signature = ComputeSignature(bookingId, paymentId, amount);
        var paymentUrl = $"https://sandbox.vnpayment.vn/paymentv2/vpcpay.html?paymentId={paymentId}&vnp_TxnRef={paymentReference}";

        return new InitiatePaymentResponse(paymentId, paymentUrl, paymentReference, amount, signature);
    }

    public async Task ConfirmAsync(int bookingId, int paymentId, string? signature, string? providerReference)
    {
        using var conn = new SqlConnection(_connectionString);

        // 1. Xác thực chữ ký (callback phải trình chữ ký hợp lệ)
        var amount = await GetPaymentAmountAsync(conn, bookingId, paymentId);
        if (amount is null)
            throw new ArgumentException("Payment không tồn tại hoặc không thuộc Booking.");

        if (string.IsNullOrEmpty(signature) ||
            !CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(signature),
                Encoding.UTF8.GetBytes(ComputeSignature(bookingId, paymentId, amount.Value))))
            throw new UnauthorizedAccessException("Chữ ký thanh toán không hợp lệ.");

        // 2. Idempotency: đã Confirmed => trả thành công, không xử lý lại
        var status = await GetPaymentStatusAsync(conn, bookingId, paymentId);
        if (status == "Confirmed")
            return;

        var p = new DynamicParameters();
        p.Add("@BookingID", bookingId, DbType.Int32);
        p.Add("@PaymentID", paymentId, DbType.Int32);
        p.Add("@ProviderReference", providerReference, DbType.String, size: 64);
        await conn.ExecuteAsync("sp_ConfirmPayment", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> ProcessRefundAsync(int paymentId, decimal refundAmount, string reason, int actorUserId)
    {
        using var conn = new SqlConnection(_connectionString);

        var p = new DynamicParameters();
        p.Add("@PaymentID", paymentId, DbType.Int32);
        p.Add("@RefundAmount", refundAmount, DbType.Decimal);
        p.Add("@RefundReason", reason, DbType.String, size: 255);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@RefundReference", $"REF-{Guid.NewGuid():N}".Substring(0, 16).ToUpperInvariant(), DbType.String, size: 50);
        p.Add("@NewRefundID", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_ProcessRefund", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewRefundID");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private async Task<decimal?> GetPaymentAmountAsync(SqlConnection conn, int bookingId, int paymentId)
        => await conn.QuerySingleOrDefaultAsync<decimal?>(
            "SELECT Amount FROM Payment WHERE PaymentID = @PaymentID AND BookingID = @BookingID",
            new { PaymentID = paymentId, BookingID = bookingId });

    private async Task<string?> GetPaymentStatusAsync(SqlConnection conn, int bookingId, int paymentId)
        => await conn.QuerySingleOrDefaultAsync<string?>(
            "SELECT PaymentStatus FROM Payment WHERE PaymentID = @PaymentID AND BookingID = @BookingID",
            new { PaymentID = paymentId, BookingID = bookingId });

    private string ComputeSignature(int bookingId, int paymentId, decimal amount)
    {
        var payload = $"{bookingId}:{paymentId}:{amount.ToString("0.##", System.Globalization.CultureInfo.InvariantCulture)}";
        using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(_signatureSecret));
        var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(payload));
        return Convert.ToHexString(hash).ToLowerInvariant();
    }
}