using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class PaymentRepository : IPaymentRepository
{
    private readonly string _connectionString;

    public PaymentRepository(string connectionString)
    {
        _connectionString = connectionString;
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

        // Dummy Payment URL (simulate VNPay, Momo)
        var paymentUrl = $"https://sandbox.vnpayment.vn/paymentv2/vpcpay.html?paymentId={paymentId}&vnp_TxnRef={paymentReference}";

        return new InitiatePaymentResponse(paymentId, paymentUrl, paymentReference, amount);
    }

    public async Task ConfirmAsync(int bookingId, int paymentId, string? providerReference)
    {
        using var conn = new SqlConnection(_connectionString);

        var p = new DynamicParameters();
        p.Add("@BookingID", bookingId, DbType.Int32);
        p.Add("@PaymentID", paymentId, DbType.Int32);
        p.Add("@ProviderReference", providerReference, DbType.String, size: 100);

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
        
        // This parameter does not seem to exist in DB based on typical schema, but we pass what sp_ProcessRefund expects
        // Usually, provider ref or something is passed. The plan said:
        // @RefundReference (Optional)
        p.Add("@RefundReference", $"REF-{Guid.NewGuid().ToString().Substring(0, 8).ToUpper()}", DbType.String, size: 50);
        p.Add("@NewRefundID", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_ProcessRefund", p, commandType: CommandType.StoredProcedure);

        return p.Get<int>("@NewRefundID");
    }
}
