using System.Data;
using System.Security.Claims;
using Dapper;
using Microsoft.AspNetCore.Http;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Data;

/// <summary>
/// Triển khai <see cref="IDbConnectionFactory"/> cho SQL Server.
///
/// SESSION_CONTEXT bám theo SESSION chứ không theo request, và connection pool tái sử dụng
/// session giữa các request khác nhau — nên context PHẢI được set lại mỗi lần mở connection,
/// không phải set một lần lúc khởi động. Dùng @read_only = 1 để giá trị không thể bị ghi đè
/// bởi câu lệnh phát sinh sau đó trong cùng phiên.
/// </summary>
public sealed class SqlConnectionFactory : IDbConnectionFactory
{
    private readonly string _connectionString;
    private readonly IHttpContextAccessor _httpContextAccessor;

    public SqlConnectionFactory(string connectionString, IHttpContextAccessor httpContextAccessor)
    {
        _connectionString = connectionString;
        _httpContextAccessor = httpContextAccessor;
    }

    public async Task<IDbConnection> OpenAsync(CancellationToken ct = default)
    {
        var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        var userId = GetCurrentUserId();
        if (userId.HasValue)
            await SetSessionUserAsync(conn, userId.Value, ct);

        return conn;
    }

    public async Task<IDbConnection> OpenForSystemAsync(CancellationToken ct = default)
    {
        var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        // Tài khoản dự trữ 'system' là ActorUserID cho SIP1–SIP5 (§12.17.1, D14).
        var systemUserId = await conn.QuerySingleOrDefaultAsync<int?>(
            new CommandDefinition(
                "SELECT UserID FROM UserAccount WHERE Username = 'system';",
                cancellationToken: ct));

        if (systemUserId.HasValue)
            await SetSessionUserAsync(conn, systemUserId.Value, ct);

        return conn;
    }

    private int? GetCurrentUserId()
    {
        var user = _httpContextAccessor.HttpContext?.User;
        if (user?.Identity?.IsAuthenticated != true) return null;

        var sub = user.FindFirstValue(ClaimTypes.NameIdentifier) ?? user.FindFirstValue("sub");
        return int.TryParse(sub, out var id) ? id : null;
    }

    private static Task SetSessionUserAsync(SqlConnection conn, int userId, CancellationToken ct)
        => conn.ExecuteAsync(new CommandDefinition(
            "EXEC sp_set_session_context @key = N'UserID', @value = @UserID, @read_only = 1;",
            new { UserID = userId },
            cancellationToken: ct));
}
