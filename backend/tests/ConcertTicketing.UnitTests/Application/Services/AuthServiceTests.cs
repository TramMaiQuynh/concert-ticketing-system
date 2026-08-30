using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Linq;
using System.Security.Claims;
using System.Threading.Tasks;
using Xunit;
using FluentAssertions;
using Moq;
using Microsoft.Extensions.Configuration;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Application.Services;
using ConcertTicketing.Domain.Models;

namespace ConcertTicketing.UnitTests.Application.Services;

public class AuthServiceTests
{
    private readonly Mock<IUserRepository> _mockRepo;
    private readonly IConfiguration _config;
    private readonly AuthService _service;

    public AuthServiceTests()
    {
        _mockRepo = new Mock<IUserRepository>();

        var inMemorySettings = new Dictionary<string, string>
        {
            {"Jwt:Secret", "this-is-a-very-long-secret-key-for-testing-only-12345"},
            {"Jwt:Issuer", "TestIssuer"},
            {"Jwt:Audience", "TestAudience"},
            {"Jwt:AccessTokenExpiryMinutes", "15"},
            {"Jwt:RefreshTokenExpiryDays", "7"}
        };

        _config = new ConfigurationBuilder()
            .AddInMemoryCollection(inMemorySettings!)
            .Build();

        _service = new AuthService(_mockRepo.Object, _config);
    }

    [Fact]
    public async Task Login_UserNotFound_ShouldThrowUnauthorized()
    {
        _mockRepo.Setup(r => r.GetByUsernameAsync(It.IsAny<string>()))
            .ReturnsAsync((UserAccount?)null);

        var request = new LoginRequest("testuser", "password");
        
        var act = async () => await _service.LoginAsync(request);
        
        await act.Should().ThrowAsync<UnauthorizedAccessException>()
            .WithMessage("Tên đăng nhập hoặc mật khẩu không đúng.");
    }

    [Fact]
    public async Task Login_WrongPassword_ShouldThrowUnauthorized()
    {
        var user = new UserAccount
        {
            Username = "testuser",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("correctpassword")
        };
        _mockRepo.Setup(r => r.GetByUsernameAsync("testuser")).ReturnsAsync(user);

        var request = new LoginRequest("testuser", "wrongpassword");
        
        var act = async () => await _service.LoginAsync(request);
        
        await act.Should().ThrowAsync<UnauthorizedAccessException>()
            .WithMessage("Tên đăng nhập hoặc mật khẩu không đúng.");
    }

    [Fact]
    public async Task Login_Success_ShouldReturnTokenPair()
    {
        var user = new UserAccount
        {
            UserID = 1,
            Username = "testuser",
            Email = "test@example.com",
            PasswordHash = BCrypt.Net.BCrypt.HashPassword("correctpassword")
        };
        _mockRepo.Setup(r => r.GetByUsernameAsync("testuser")).ReturnsAsync(user);
        _mockRepo.Setup(r => r.GetRolesAsync(1)).ReturnsAsync(new[] { "Customer" });
        _mockRepo.Setup(r => r.CreateRefreshTokenAsync(1, It.IsAny<DateTime>()))
            .ReturnsAsync("raw-refresh-token");

        var request = new LoginRequest("testuser", "correctpassword");
        
        var (auth, refreshToken) = await _service.LoginAsync(request);
        
        auth.Should().NotBeNull();
        auth.AccessToken.Should().NotBeEmpty();
        auth.TokenType.Should().Be("Bearer");
        auth.ExpiresIn.Should().Be(15 * 60);
        refreshToken.Should().Be("raw-refresh-token");
    }

    [Fact]
    public async Task Register_ShouldHashPasswordAndCallRepo()
    {
        _mockRepo.Setup(r => r.CreateAsync(It.IsAny<UserAccount>(), It.IsAny<string>()))
            .ReturnsAsync(1);
        _mockRepo.Setup(r => r.CreateRefreshTokenAsync(1, It.IsAny<DateTime>()))
            .ReturnsAsync("raw-refresh-token");

        var request = new RegisterRequest("newuser", "new@example.com", "Password123", "New User");
        
        var (auth, refreshToken) = await _service.RegisterAsync(request);

        _mockRepo.Verify(r => r.CreateAsync(
            It.Is<UserAccount>(u => u.Username == "newuser" && u.Email == "new@example.com" && u.DisplayName == "New User"),
            It.Is<string>(hash => VerifyHash("Password123", hash))), Times.Once);
            
        auth.AccessToken.Should().NotBeEmpty();
    }

    private static bool VerifyHash(string password, string hash)
    {
        return BCrypt.Net.BCrypt.Verify(password, hash);
    }

    [Fact]
    public async Task Register_ShouldReturnTokenWithCustomerRole()
    {
        _mockRepo.Setup(r => r.CreateAsync(It.IsAny<UserAccount>(), It.IsAny<string>()))
            .ReturnsAsync(1);
            
        var request = new RegisterRequest("newuser", "new@example.com", "Password123", "New User");
        var (auth, _) = await _service.RegisterAsync(request);

        var handler = new JwtSecurityTokenHandler();
        var jwtToken = handler.ReadJwtToken(auth.AccessToken);
        var roleClaims = jwtToken.Claims.Where(c => c.Type == ClaimTypes.Role || c.Type == "role").Select(c => c.Value);
        
        roleClaims.Should().Contain("Customer");
    }

    [Fact]
    public async Task Refresh_InvalidToken_ShouldThrowUnauthorized()
    {
        _mockRepo.Setup(r => r.ValidateRefreshTokenAsync("invalid"))
            .ReturnsAsync((0, false));

        var act = async () => await _service.RefreshAsync("invalid");
        
        await act.Should().ThrowAsync<UnauthorizedAccessException>()
            .WithMessage("Refresh token không hợp lệ hoặc đã hết hạn.");
    }

    [Fact]
    public async Task Refresh_UserInactive_ShouldThrowUnauthorized()
    {
        _mockRepo.Setup(r => r.ValidateRefreshTokenAsync("valid-token"))
            .ReturnsAsync((1, true));
        _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync((UserAccount?)null);

        var act = async () => await _service.RefreshAsync("valid-token");
        
        await act.Should().ThrowAsync<UnauthorizedAccessException>()
            .WithMessage("Tài khoản không còn hoạt động.");
    }

    [Fact]
    public async Task Refresh_Success_ShouldRevokeOldAndIssueNew()
    {
        var user = new UserAccount { UserID = 1, Username = "testuser" };
        
        _mockRepo.Setup(r => r.ValidateRefreshTokenAsync("old-token")).ReturnsAsync((1, true));
        _mockRepo.Setup(r => r.GetByIdAsync(1)).ReturnsAsync(user);
        _mockRepo.Setup(r => r.GetRolesAsync(1)).ReturnsAsync(new[] { "Customer" });
        _mockRepo.Setup(r => r.CreateRefreshTokenAsync(1, It.IsAny<DateTime>())).ReturnsAsync("new-token");

        var (auth, refreshToken) = await _service.RefreshAsync("old-token");

        // Verify rotation
        _mockRepo.Verify(r => r.RevokeRefreshTokenAsync("old-token"), Times.Once);
        _mockRepo.Verify(r => r.CreateRefreshTokenAsync(1, It.IsAny<DateTime>()), Times.Once);
        
        refreshToken.Should().Be("new-token");
        auth.AccessToken.Should().NotBeEmpty();
    }

    [Fact]
    public async Task Logout_ShouldCallRevoke()
    {
        await _service.LogoutAsync("some-token");
        
        _mockRepo.Verify(r => r.RevokeRefreshTokenAsync("some-token"), Times.Once);
    }

    [Fact]
    public async Task GenerateAccessToken_ShouldContainCorrectClaims()
    {
        var user = new UserAccount
        {
            UserID = 99,
            Email = "tester@example.com",
            DisplayName = "Test Display"
        };
        _mockRepo.Setup(r => r.GetByUsernameAsync("testuser")).ReturnsAsync(user);
        _mockRepo.Setup(r => r.GetRolesAsync(99)).ReturnsAsync(new[] { "Admin", "Staff" });
        // Hack to get the token directly by calling Login with correct password hash
        user.PasswordHash = BCrypt.Net.BCrypt.HashPassword("pass");
        
        var (auth, _) = await _service.LoginAsync(new LoginRequest("testuser", "pass"));

        var handler = new JwtSecurityTokenHandler();
        var token = handler.ReadJwtToken(auth.AccessToken);

        token.Issuer.Should().Be("TestIssuer");
        token.Audiences.Should().Contain("TestAudience");
        
        token.Claims.Should().Contain(c => c.Type == JwtRegisteredClaimNames.Sub && c.Value == "99");
        token.Claims.Should().Contain(c => c.Type == JwtRegisteredClaimNames.Email && c.Value == "tester@example.com");
        token.Claims.Should().Contain(c => c.Type == "displayName" && c.Value == "Test Display");
        
        var roles = token.Claims.Where(c => c.Type == ClaimTypes.Role).Select(c => c.Value);
        roles.Should().Contain(new[] { "Admin", "Staff" });
        
        token.ValidTo.Should().BeCloseTo(DateTime.UtcNow.AddMinutes(15), TimeSpan.FromMinutes(1));
    }
}
