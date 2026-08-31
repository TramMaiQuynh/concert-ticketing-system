using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests.Infrastructure;

/// <summary>
/// Kết nối DB thật (ConcertTicketingDB trên .\SQLEXPRESS).
/// - AdminConnectionString (Windows Auth): seed/cleanup/verify.
/// - ApiConnectionString (api_service): đúng principal backend sản phẩm
///   → mọi repository test với least-privilege thật (bắt lỗi thiếu GRANT).
/// Dữ liệu test dùng suffix duy nhất và được dọn sạch sau mỗi test-class.
/// </summary>
public sealed partial class DbFixture : IAsyncLifetime
{
    public const string DbName = "ConcertTicketingDB";

    public string AdminConnectionString { get; } =
        $"Server=.\\SQLEXPRESS;Database={DbName};Trusted_Connection=True;TrustServerCertificate=True;Connection Timeout=30;";

    public string ApiConnectionString { get; } =
        $"Server=.\\SQLEXPRESS;Database={DbName};User Id=api_service;Password=YourStrongPassword!;TrustServerCertificate=True;Connection Timeout=30;";

    public string PaymentSignatureSecret { get; } = "REPLACE_WITH_PAYMENT_SIGNATURE_SECRET";

    public string Suffix { get; } = Guid.NewGuid().ToString("N")[..8];

    public Task InitializeAsync()
    {
        using var admin = new SqlConnection(AdminConnectionString);
        admin.Open();
        var spCount = admin.QuerySingle<int>(
            "SELECT COUNT(*) FROM sys.procedures WHERE is_ms_shipped = 0;");
        if (spCount < 20)
            throw new InvalidOperationException(
                $"DB chưa deploy đầy đủ (chỉ có {spCount} stored procedure).");

        using var api = new SqlConnection(ApiConnectionString);
        api.Open();

        return Task.CompletedTask;
    }

    public async Task DisposeAsync() => await CleanupSuffixAsync();

    public async Task<int> ExecAdminAsync(string sql, object? param = null)
    {
        await using var conn = new SqlConnection(AdminConnectionString);
        return await conn.ExecuteAsync(sql, param);
    }

    public async Task<T?> QueryAdminAsync<T>(string sql, object? param = null)
    {
        await using var conn = new SqlConnection(AdminConnectionString);
        return await conn.QuerySingleOrDefaultAsync<T>(sql, param);
    }

    public async Task<List<T>> QueryAdminListAsync<T>(string sql, object? param = null)
    {
        await using var conn = new SqlConnection(AdminConnectionString);
        return (await conn.QueryAsync<T>(sql, param)).ToList();
    }
}