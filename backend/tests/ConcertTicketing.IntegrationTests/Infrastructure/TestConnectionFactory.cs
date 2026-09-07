using System.Data;
using System.Security.Claims;
using Dapper;
using Microsoft.AspNetCore.Http;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.IntegrationTests.Infrastructure;

/// <summary>
/// Factory kết nối cho integration test.
///
/// Mặc định KHÔNG set SESSION_CONTEXT — mô phỏng đúng lời gọi không có danh tính
/// (webhook, background job). Muốn kiểm tra Row-Level Security thì dùng
/// <see cref="AsUser"/> để giả lập một người dùng đã đăng nhập, y như
/// SqlConnectionFactory làm trong production.
/// </summary>
public sealed class TestConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;
    private readonly int? _userId;

    public TestConnectionFactory(string connectionString, int? userId = null)
    {
        _connectionString = connectionString;
        _userId = userId;
    }

    /// <summary>Trả về factory mới đóng vai người dùng chỉ định (để test RLS).</summary>
    public TestConnectionFactory AsUser(int userId) => new(_connectionString, userId);

    public async Task<IDbConnection> OpenAsync(CancellationToken ct = default)
    {
        var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        if (_userId.HasValue) await SetSessionUserAsync(conn, _userId.Value, ct);
        return conn;
    }

    public async Task<IDbConnection> OpenForSystemAsync(CancellationToken ct = default)
    {
        var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);
        var systemUserId = await conn.QuerySingleOrDefaultAsync<int?>(
            new CommandDefinition("SELECT UserID FROM UserAccount WHERE Username = 'system';",
                cancellationToken: ct));
        if (systemUserId.HasValue) await SetSessionUserAsync(conn, systemUserId.Value, ct);
        return conn;
    }

    private static Task SetSessionUserAsync(SqlConnection conn, int userId, CancellationToken ct)
        => conn.ExecuteAsync(new CommandDefinition(
            "EXEC sp_set_session_context @key = N'UserID', @value = @UserID, @read_only = 1;",
            new { UserID = userId }, cancellationToken: ct));
}
