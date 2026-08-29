using System.Data;
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

    public async Task<UserAccount?> GetByUsernameAsync(string username)
    {
        using var conn = new SqlConnection(_connectionString);

        return await conn.QuerySingleOrDefaultAsync<UserAccount>(
            @"SELECT UserID, Username, Email, PasswordHash, FullName, AccountStatus, CreatedAt
              FROM UserAccount
              WHERE Username = @Username AND AccountStatus = 'Active'",
            new { Username = username });
    }

    public async Task<IEnumerable<string>> GetRolesAsync(int userId)
    {
        using var conn = new SqlConnection(_connectionString);

        return await conn.QueryAsync<string>(
            @"SELECT r.RoleName
              FROM UserRoleAssignment ura
              JOIN Role r ON ura.RoleID = r.RoleID
              WHERE ura.UserID = @UserID",
            new { UserID = userId });
    }

    public async Task<int> CreateAsync(UserAccount user, string passwordHash)
    {
        using var conn = new SqlConnection(_connectionString);

        // BCrypt hash đã chứa salt bên trong — không cần cột PasswordSalt riêng
        var userId = await conn.QuerySingleAsync<int>(
            @"INSERT INTO UserAccount (Username, Email, PasswordHash, FullName, AccountStatus, CreatedAt)
              OUTPUT INSERTED.UserID
              VALUES (@Username, @Email, @PasswordHash, @FullName, 'Active', GETUTCDATE())",
            new
            {
                user.Username,
                user.Email,
                PasswordHash = passwordHash,
                user.FullName
            });

        // Gán role Customer mặc định
        await conn.ExecuteAsync(
            @"INSERT INTO UserRoleAssignment (UserID, RoleID)
              SELECT @UserID, RoleID FROM Role WHERE RoleName = 'Customer'",
            new { UserID = userId });

        return userId;
    }
}