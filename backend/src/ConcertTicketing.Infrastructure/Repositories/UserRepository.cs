using System.Data;
using System.Security.Cryptography;
using System.Text;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Domain.Models;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class UserRepository : IUserRepository
{
    private readonly IDbConnectionFactory _factory;

    public UserRepository(IDbConnectionFactory factory)
    {
        _factory = factory;
    }

    // ── Query ─────────────────────────────────────────────────────────────────

    public async Task<UserAccount?> GetByUsernameAsync(string username)
    {
        using var conn = await _factory.OpenAsync();

        // Dùng đúng tên cột DB: DisplayName, CreatedTimestamp (không phải FullName, CreatedAt)
        //
        // PasswordHash IS NOT NULL: tài khoản không có mật khẩu thì KHÔNG thể đăng nhập.
        // Cụ thể là tài khoản dự trữ 'system' (§12.17.1 / §23.7) — nó có AccountStatus =
        // 'Active' nên vẫn lọt qua điều kiện trạng thái, và trước đây BCrypt.Verify sẽ
        // được gọi với hash null: ném exception lạ thay vì 401, đồng thời phản hồi khác
        // biệt đó tiết lộ rằng tài khoản 'system' có tồn tại.
        // Đặt điều kiện ở đây (thay vì liệt kê tên tài khoản) để đúng với mọi tài khoản
        // dịch vụ thêm về sau.
        //
        // DbType.AnsiString: UserAccount.Username là VARCHAR(64) có UNIQUE INDEX. Tham số
        // string trần qua object ẩn danh được Dapper suy ra NVARCHAR theo mặc định — so
        // sánh NVARCHAR với cột VARCHAR buộc SQL Server ngầm ép kiểu CỘT (ưu tiên kiểu
        // Unicode cao hơn), vô hiệu hoá index seek trên UNIQUE INDEX và quét toàn bảng ở
        // MỌI lượt đăng nhập. Đã đo trên bảng 50.000 dòng: 149 logical reads (scan) so với
        // 2 (seek) khi tham số đúng kiểu — không sai kết quả, chỉ sai hiệu năng, nhưng sai
        // ngay trên đường nóng nhất của hệ thống.
        var p = new DynamicParameters();
        p.Add("@Username", username, DbType.AnsiString, size: 64);

        return await conn.QuerySingleOrDefaultAsync<UserAccount>(
            @"SELECT UserID, Username, Email, PasswordHash, DisplayName, AccountStatus, CreatedTimestamp
              FROM UserAccount
              WHERE Username = @Username
                AND AccountStatus = 'Active'
                AND PasswordHash IS NOT NULL",
            p);
    }

    public async Task<UserAccount?> GetByIdAsync(int userId)
    {
        using var conn = await _factory.OpenAsync();

        return await conn.QuerySingleOrDefaultAsync<UserAccount>(
            @"SELECT UserID, Username, Email, DisplayName, AccountStatus, CreatedTimestamp
              FROM UserAccount
              WHERE UserID = @UserID AND AccountStatus = 'Active'",
            new { UserID = userId });
    }

    public async Task<IEnumerable<string>> GetRolesAsync(int userId)
    {
        using var conn = await _factory.OpenAsync();

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
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        // DbType.AnsiString: sp_RegisterUser khai bao @Username VARCHAR(64).
        p.Add("@Username", user.Username, DbType.AnsiString, size: 64);
        p.Add("@Email", user.Email);
        p.Add("@PasswordHash", passwordHash);
        p.Add("@DisplayName", user.DisplayName);
        p.Add("@NewUserID", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_RegisterUser", p, commandType: CommandType.StoredProcedure);

        return p.Get<int>("@NewUserID");
    }

    // ── Refresh Token ─────────────────────────────────────────────────────────

    public async Task<string> CreateRefreshTokenAsync(int userId, DateTime expiryUtc)
    {
        using var conn = await _factory.OpenAsync();

        // Tạo raw token 64 bytes (an toàn mật mã — không dùng Guid vì entropy thấp)
        var rawToken = Convert.ToBase64String(RandomNumberGenerator.GetBytes(64));
        var tokenHash = ComputeSha256Hex(rawToken);

        await conn.ExecuteAsync(
            @"INSERT INTO RefreshToken (UserID, TokenHash, ExpiryDatetime, IsRevoked)
              VALUES (@UserID, @TokenHash, @ExpiryDatetime, 0)",
            new { UserID = userId, TokenHash = tokenHash, ExpiryDatetime = expiryUtc });

        return rawToken; // Chỉ raw token được gửi cho client — DB không bao giờ lưu raw
    }

    /// <summary>
    /// Trả về TRẠNG THÁI của token chứ không chỉ hợp lệ/không hợp lệ.
    /// Phân biệt "đã bị thu hồi" với "không tồn tại" là điều kiện bắt buộc để phát hiện
    /// refresh token bị dùng lại (xem AuthService.RefreshAsync).
    /// </summary>
    public async Task<RefreshTokenValidation> ValidateRefreshTokenAsync(string rawToken)
    {
        using var conn = await _factory.OpenAsync();
        var tokenHash = ComputeSha256Hex(rawToken);

        var row = await conn.QuerySingleOrDefaultAsync<RefreshTokenRow>(
            @"SELECT UserID, IsRevoked,
                     CAST(CASE WHEN ExpiryDatetime > SYSUTCDATETIME() THEN 1 ELSE 0 END AS BIT) AS IsAlive
              FROM RefreshToken
              WHERE TokenHash = @TokenHash",
            new { TokenHash = tokenHash });

        if (row == null)
            return new RefreshTokenValidation(0, RefreshTokenState.NotFound);
        if (row.IsRevoked)
            return new RefreshTokenValidation(row.UserID, RefreshTokenState.Revoked);
        if (!row.IsAlive)
            return new RefreshTokenValidation(row.UserID, RefreshTokenState.Expired);

        return new RefreshTokenValidation(row.UserID, RefreshTokenState.Valid);
    }

    /// <summary>
    /// Thu hồi toàn bộ refresh token còn hiệu lực của một user.
    /// Dùng khi phát hiện một token đã thu hồi bị trình lại: không thể biết bản sao nào
    /// đang nằm trong tay kẻ tấn công, nên cắt sạch cả chuỗi và buộc đăng nhập lại.
    /// </summary>
    public async Task<int> RevokeAllRefreshTokensForUserAsync(int userId)
    {
        using var conn = await _factory.OpenAsync();

        return await conn.ExecuteAsync(
            "UPDATE RefreshToken SET IsRevoked = 1 WHERE UserID = @UserID AND IsRevoked = 0",
            new { UserID = userId });
    }

    public async Task RevokeRefreshTokenAsync(string rawToken)
    {
        using var conn = await _factory.OpenAsync();
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
        public bool IsRevoked { get; set; }
        public bool IsAlive { get; set; }
    }
}