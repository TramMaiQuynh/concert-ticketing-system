using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Domain.Models;

namespace ConcertTicketing.Application.Services;

public interface IAuthService
{
    // Trả về (AuthResponse, rawRefreshToken).
    // Controller có trách nhiệm set rawRefreshToken vào HttpOnly Cookie.
    Task<(AuthResponse Auth, string RawRefreshToken)> LoginAsync(LoginRequest request);
    Task<(AuthResponse Auth, string RawRefreshToken)> RegisterAsync(RegisterRequest request);
    Task<(AuthResponse Auth, string RawRefreshToken)> RefreshAsync(string rawRefreshToken);
    Task LogoutAsync(string rawRefreshToken);
}

public class AuthService : IAuthService
{
    private readonly IUserRepository _userRepository;
    private readonly IConfiguration _config;

    public AuthService(IUserRepository userRepository, IConfiguration config)
    {
        _userRepository = userRepository;
        _config         = config;
    }

    // ── Login ─────────────────────────────────────────────────────────────────

    public async Task<(AuthResponse Auth, string RawRefreshToken)> LoginAsync(LoginRequest request)
    {
        var user = await _userRepository.GetByUsernameAsync(request.Username)
            ?? throw new UnauthorizedAccessException("Tên đăng nhập hoặc mật khẩu không đúng.");

        // BCrypt.Verify đọc salt nhúng trong chuỗi hash ($2a$12$...)
        // → Không cần cột PasswordSalt riêng
        if (!BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            throw new UnauthorizedAccessException("Tên đăng nhập hoặc mật khẩu không đúng.");

        var roles = await _userRepository.GetRolesAsync(user.UserID);
        return await IssueTokenPairAsync(user, roles);
    }

    // ── Register ──────────────────────────────────────────────────────────────

    public async Task<(AuthResponse Auth, string RawRefreshToken)> RegisterAsync(RegisterRequest request)
    {
        // workFactor=12: khoảng 250ms/lần hash trên phần cứng hiện đại.
        // Đủ chậm để chống Brute Force, đủ nhanh để UX chấp nhận được.
        var passwordHash = BCrypt.Net.BCrypt.HashPassword(request.Password, workFactor: 12);

        var user = new UserAccount
        {
            Username    = request.Username,
            Email       = request.Email,
            DisplayName = request.DisplayName  // đúng với cột DB
        };

        var userId = await _userRepository.CreateAsync(user, passwordHash);
        user.UserID = userId;

        // Người dùng mới luôn có role Customer
        return await IssueTokenPairAsync(user, new[] { "Customer" });
    }

    // ── Refresh ───────────────────────────────────────────────────────────────

    public async Task<(AuthResponse Auth, string RawRefreshToken)> RefreshAsync(string rawRefreshToken)
    {
        var (userId, isValid) = await _userRepository.ValidateRefreshTokenAsync(rawRefreshToken);

        if (!isValid || userId == 0)
            throw new UnauthorizedAccessException("Refresh token không hợp lệ hoặc đã hết hạn.");

        // Thu hồi token cũ TRƯỚC khi cấp token mới (Refresh Token Rotation).
        // Mục đích: nếu token cũ bị đánh cắp và được dùng lại → hệ thống phát hiện
        // (token đã revoked) → buộc đăng nhập lại.
        await _userRepository.RevokeRefreshTokenAsync(rawRefreshToken);

        // Lấy lại thông tin user để tạo Access Token đầy đủ claims
        var user = await _userRepository.GetByIdAsync(userId)
            ?? throw new UnauthorizedAccessException("Tài khoản không còn hoạt động.");

        var roles = await _userRepository.GetRolesAsync(userId);
        return await IssueTokenPairAsync(user, roles);
    }

    // ── Logout ────────────────────────────────────────────────────────────────

    public async Task LogoutAsync(string rawRefreshToken)
    {
        // Chỉ cần revoke token trong DB — Access Token sẽ tự hết hạn sau ExpiryMinutes
        await _userRepository.RevokeRefreshTokenAsync(rawRefreshToken);
    }

    // ── Private helpers ───────────────────────────────────────────────────────

    private async Task<(AuthResponse Auth, string RawRefreshToken)> IssueTokenPairAsync(
        UserAccount user, IEnumerable<string> roles)
    {
        var accessToken  = GenerateAccessToken(user, roles);
        var expiryMin    = int.Parse(_config["Jwt:AccessTokenExpiryMinutes"]!);
        var refreshDays  = int.Parse(_config["Jwt:RefreshTokenExpiryDays"]!);

        var rawRefresh = await _userRepository.CreateRefreshTokenAsync(
            user.UserID,
            DateTime.UtcNow.AddDays(refreshDays));

        return (new AuthResponse(accessToken, "Bearer", expiryMin * 60), rawRefresh);
    }

    private string GenerateAccessToken(UserAccount user, IEnumerable<string> roles)
    {
        var jwtSecret    = _config["Jwt:Secret"]!;
        var jwtIssuer    = _config["Jwt:Issuer"]!;
        var jwtAudience  = _config["Jwt:Audience"]!;
        var expiryMin    = int.Parse(_config["Jwt:AccessTokenExpiryMinutes"]!);

        var key   = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            // sub = UserID (chuẩn JWT RFC 7519) — Controller đọc bằng ClaimTypes.NameIdentifier
            new(JwtRegisteredClaimNames.Sub,  user.UserID.ToString()),
            new(JwtRegisteredClaimNames.Jti,  Guid.NewGuid().ToString()), // unique per token
        };

        // Chỉ thêm nếu có dữ liệu (user từ Refresh flow có thể thiếu Email/DisplayName)
        if (!string.IsNullOrEmpty(user.Email))
            claims.Add(new(JwtRegisteredClaimNames.Email, user.Email));
        if (!string.IsNullOrEmpty(user.DisplayName))
            claims.Add(new("displayName", user.DisplayName));

        // Mỗi role là 1 Claim riêng — ASP.NET Core Authorization đọc qua ClaimTypes.Role
        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r)));

        var token = new JwtSecurityToken(
            issuer:             jwtIssuer,
            audience:           jwtAudience,
            claims:             claims,
            expires:            DateTime.UtcNow.AddMinutes(expiryMin),
            signingCredentials: creds);

        return new JwtSecurityTokenHandler().WriteToken(token);
    }
}
