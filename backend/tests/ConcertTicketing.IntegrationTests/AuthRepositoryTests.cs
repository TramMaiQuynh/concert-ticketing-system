using ConcertTicketing.Domain.Models;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho AuthRepository/UserRepository chạy với connection API thật (api_service):
/// - RegisterUser (tạo/thành công, trùng username → 57001 → 409)
/// - Login hash verify (hashing + GetByUsername đúng dữ liệu DB)
/// - Refresh token roundtrip (CREATE/VALIDATE/REVOKE)
/// Đích: chứng minh mọi truy vấn repository chạy đúng với DB thật + least-privilege.
/// </summary>
public sealed class AuthRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public AuthRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private UserRepository Repo() => new(_fx.ApiFactory);

    [Fact(DisplayName = "RegisterUser: tạo thành công, trả NewUserID, gán role Customer")]
    public async Task RegisterUser_CreatesUser_WithCustomerRole()
    {
        var s = NewSeeder();
        var username = s.Username("authcust");
        var user = new UserAccount
        {
            Username = username,
            Email = $"{username}@test.local",
            DisplayName = "IT Auth Customer"
        };

        var id = await Repo().CreateAsync(user, "fake-hash-for-test");

        id.Should().BeGreaterThan(0);

        var roles = (await Repo().GetRolesAsync(id)).ToList();
        roles.Should().Contain("Customer");

        var reloaded = await Repo().GetByUsernameAsync(username);
        reloaded.Should().NotBeNull();
        reloaded!.Username.Should().Be(username);
        reloaded.AccountStatus.Should().Be("Active");
        reloaded.PasswordHash.Should().Be("fake-hash-for-test");
    }

    [Fact(DisplayName = "RegisterUser: username trùng → SqlException 57001 (HTTP 409)")]
    public async Task RegisterUser_DuplicateUsername_Throws57001()
    {
        var s = NewSeeder();
        var username = s.Username("dup");
        var user = new UserAccount
        {
            Username = username,
            Email = $"{username}@test.local",
            DisplayName = "Dup"
        };

        await Repo().CreateAsync(user, "hash-1");
        // Lần thứ 2 → sp_RegisterUser THROW 57001 (username đã tồn tại)
        var act = () => Repo().CreateAsync(user, "hash-2");

        await act.Should().ThrowAsync<SqlException>().Where(e => e.Number == 57001);
    }

    [Fact(DisplayName = "Login hash: hash lưu đúng, GetByUsername trả về đúng DB record")]
    public async Task Login_HashStoredAndRetrieved()
    {
        var s = NewSeeder();
        var username = s.Username("loginhash");
        var hash = "$2a$12$abcdefghijklmnopqrstuvabcdefghijklmnopqrstuvabcdefghijklmn";
        var user = new UserAccount
        {
            Username = username,
            Email = $"{username}@test.local",
            DisplayName = "Login Hash"
        };

        var id = await Repo().CreateAsync(user, hash);
        id.Should().BeGreaterThan(0);

        var fetched = await Repo().GetByUsernameAsync(username);
        fetched.Should().NotBeNull();
        fetched!.PasswordHash.Should().Be(hash);
        fetched.UserID.Should().Be(id);

        var byId = await Repo().GetByIdAsync(id);
        byId.Should().NotBeNull();
        byId!.Username.Should().Be(username);
    }

    [Fact(DisplayName = "RefreshToken: create → validate valid → revoke → validate invalid")]
    public async Task RefreshToken_Roundtrip()
    {
        var s = NewSeeder();
        var userId = await s.CreateUserAsync("Customer");

        var repo = Repo();
        var rawToken = await repo.CreateRefreshTokenAsync(userId, DateTime.UtcNow.AddDays(7));
        rawToken.Should().NotBeNullOrEmpty();

        var ok = await repo.ValidateRefreshTokenAsync(rawToken);
        ok.UserId.Should().Be(userId);
        ok.State.Should().Be(RefreshTokenState.Valid);

        await repo.RevokeRefreshTokenAsync(rawToken);

        // Phải phân biệt được "đã thu hồi" với "không tồn tại": đó là điều kiện để
        // AuthService phát hiện refresh token bị dùng lại.
        var revoked = await repo.ValidateRefreshTokenAsync(rawToken);
        revoked.UserId.Should().Be(userId);
        revoked.State.Should().Be(RefreshTokenState.Revoked);
        revoked.IsValid.Should().BeFalse();

        // Token không tồn tại
        var unknown = await repo.ValidateRefreshTokenAsync("nonexistent-token");
        unknown.UserId.Should().Be(0);
        unknown.State.Should().Be(RefreshTokenState.NotFound);
    }

    [Fact(DisplayName = "RevokeAll: thu hồi toàn bộ token còn hiệu lực của user")]
    public async Task RevokeAllRefreshTokens_RevokesEveryLiveToken()
    {
        var s = NewSeeder();
        var userId = await s.CreateUserAsync("Customer");
        var repo = Repo();

        var t1 = await repo.CreateRefreshTokenAsync(userId, DateTime.UtcNow.AddDays(7));
        var t2 = await repo.CreateRefreshTokenAsync(userId, DateTime.UtcNow.AddDays(7));

        var affected = await repo.RevokeAllRefreshTokensForUserAsync(userId);
        affected.Should().BeGreaterThanOrEqualTo(2);

        (await repo.ValidateRefreshTokenAsync(t1)).State.Should().Be(RefreshTokenState.Revoked);
        (await repo.ValidateRefreshTokenAsync(t2)).State.Should().Be(RefreshTokenState.Revoked);
    }
}