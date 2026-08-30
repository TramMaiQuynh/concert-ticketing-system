using System.Data;
using System.Security.Cryptography;
using System.Text;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Domain.Models;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class UserRepository : IUserRepository
{
    private readonly string _connectionString;

    public UserRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    // ── Query ─────────────────────────────────────────────────────────────────

    public async Task<UserAccount?> GetByUsernameAsync(string username)
    {
        using var conn = new SqlConnection(_connectionString);

        // Dùng đúng tên cột DB: DisplayName, CreatedTimestamp (không phải FullName, CreatedAt)
        return await conn.QuerySingleOrDefaultAsync<UserAccount>(
            @"SELECT UserID, Username, Email, PasswordHash, DisplayName, AccountStatus, CreatedTimestamp
              FROM UserAccount
              WHERE Username = @Username AND AccountStatus = 'Active'",
            new { Username = username });
    }

    public async Task<UserAccount?> GetByIdAsync(int userId)
    {
        using var conn = new SqlConnection(_connectionString);

        return await conn.QuerySingleOrDefaultAsync<UserAccount>(
            @"SELECT UserID, Username, Email, DisplayName, AccountStatus, CreatedTimestamp
              FROM UserAccount
              WHERE UserID = @UserID AND AccountStatus = 'Active'",
            new { UserID = userId });
    }

    public async Task<IEnumerable<string>> GetRolesAsync(int userId)
    {
        using var conn = new SqlConnection(_connectionString);

        // Chỉ lấy role đang Active (AssignmentStatus = 'Active')
        return await conn.QueryAsync<string>(
            @"SELECT r.RoleName
              FROM UserRoleAssignment ura
              JOIN Role r ON ura.RoleID = r.RoleID
              WHERE ura.UserID = @UserID AND ura.AssignmentStatus = 'Active' AND r.RoleStatus = 'Active'",
            new { UserID = userId });
    }

    // ── Command ───────────────────────────────────────────────────────────────

    public async Task<int> CreateAsync(UserAccount user, string passwordHash)
    {
        using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync();

        // Dùng transaction để đảm bảo: tạo user + gán role là 1 atomic operation.
        // Nếu gán role thất bại (vd: Role 'Customer' không tồn tại), user không được tạo.
        using var tx = conn.BeginTransaction();
        try
        {
            // OUTPUT INSERTED.UserID = lấy ID vừa được IDENTITY generate, không cần SELECT thêm
            // Không INSERT CreatedTimestamp / UpdatedTimestamp — đã có DEFAULT SYSDATETIME()
            var userId = await conn.QuerySingleAsync<int>(
                @"INSERT INTO UserAccount (Username, Email, PasswordHash, DisplayName, AccountStatus)
                  OUTPUT INSERTED.UserID
                  VALUES (@Username, @Email, @PasswordHash, @DisplayName, 'Active')",
                new
                {
                    user.Username,
                    user.Email,
                    PasswordHash = passwordHash,       // BCrypt hash
                    user.DisplayName
                },
                transaction: tx);

            // AssignmentStatus là NOT NULL không có DEFAULT → phải truyền 'Active'
            await conn.ExecuteAsync(
                @"INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
                  SELECT @UserID, RoleID, 'Active'
                  FROM Role
                  WHERE RoleName = 'Customer' AND RoleStatus = 'Active'",
                new { UserID = userId },
                transaction: tx);

            tx.Commit();
            return userId;
        }
        catch
        {
            tx.Rollback();
            throw;
        }
    }

    // ── Refresh Token ─────────────────────────────────────────────────────────

    public async Task<string> CreateRefreshTokenAsync(int userId, DateTime expiryUtc)
    {
        using var conn = new SqlConnection(_connectionString);

        // Tạo raw token 64 bytes (an toàn mật mã — không dùng Guid vì entropy thấp)
        var rawToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        var tokenHash = ComputeSha256Hex(rawToken);

        await conn.ExecuteAsync(
            @"INSERT INTO RefreshToken (UserID, TokenHash, ExpiryDatetime)
              VALUES (@UserID, @TokenHash, @ExpiryDatetime)",
            new { UserID = userId, TokenHash = tokenHash, ExpiryDatetime = expiryUtc });

        return rawToken; // Chỉ raw token được gửi cho client — DB không bao giờ lưu raw
    }

    public async Task<(int UserId, bool IsValid)> ValidateRefreshTokenAsync(string rawToken)
    {
        using var conn = new SqlConnection(_connectionString);
        var tokenHash = ComputeSha256Hex(rawToken);

        // Dapper không map trực tiếp vào C# tuple → dùng private helper class
        var row = await conn.QuerySingleOrDefaultAsync<RefreshTokenRow>(
            @"SELECT UserID,
                     CAST(
                         CASE WHEN ExpiryDatetime > SYSUTCDATETIME() AND IsRevoked = 0
                              THEN 1 ELSE 0 END
                     AS BIT) AS IsValid
              FROM RefreshToken
              WHERE TokenHash = @TokenHash",
            new { TokenHash = tokenHash });

        if (row == null) return (0, false);
        return (row.UserID, row.IsValid);
    }

    public async Task RevokeRefreshTokenAsync(string rawToken)
    {
        using var conn = new SqlConnection(_connectionString);
        var tokenHash = ComputeSha256Hex(rawToken);

        // Không DELETE — set IsRevoked = 1 để giữ audit trail
        await conn.ExecuteAsync(
            "UPDATE RefreshToken SET IsRevoked = 1 WHERE TokenHash = @TokenHash",
            new { TokenHash = tokenHash });
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /// <summary>
    /// Tính SHA-256 của chuỗi đầu vào, trả về chuỗi hex 64 ký tự.
    /// Dùng để hash Refresh Token trước khi lưu DB.
    /// </summary>
    private static string ComputeSha256Hex(string input)
    {
        var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(input));
        return Convert.ToHexString(bytes).ToLowerInvariant(); // 64 ký tự hex thường
    }

    /// <summary>
    /// Private helper class để Dapper map kết quả ValidateRefreshToken.
    /// Không thể dùng C# tuple trực tiếp vì Dapper map theo tên property.
    /// </summary>
    private class RefreshTokenRow
    {
        public int UserID { get; set; }
        public bool IsValid { get; set; }
    }
}