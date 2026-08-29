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
    Task<AuthResponse> LoginAsync(LoginRequest request);
    Task<AuthResponse> RegisterAsync(RegisterRequest request);
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

    public async Task<AuthResponse> LoginAsync(LoginRequest request)
    {
        var user = await _userRepository.GetByUsernameAsync(request.Username)
            ?? throw new UnauthorizedAccessException("Tên đăng nhập hoặc mật khẩu không đúng.");

        // BCrypt.Verify tự đọc salt từ chuỗi hash ($2a$12$...)
        // Không cần cột PasswordSalt riêng
        if (!BCrypt.Net.BCrypt.Verify(request.Password, user.PasswordHash))
            throw new UnauthorizedAccessException("Tên đăng nhập hoặc mật khẩu không đúng.");

        var roles = await _userRepository.GetRolesAsync(user.UserID);
        return GenerateAuthResponse(user, roles);
    }

    public async Task<AuthResponse> RegisterAsync(RegisterRequest request)
    {
        // Hash password với BCrypt cost=12 (salt tự động tạo và nhúng vào hash)
        var hash = BCrypt.Net.BCrypt.HashPassword(request.Password, workFactor: 12);

        var user = new UserAccount
        {
            Username = request.Username,
            Email    = request.Email,
            FullName = request.FullName
        };

        var userId = await _userRepository.CreateAsync(user, hash);
        user.UserID = userId;

        return GenerateAuthResponse(user, new[] { "Customer" });
    }

    private AuthResponse GenerateAuthResponse(UserAccount user, IEnumerable<string> roles)
    {
        var jwtSecret    = _config["Jwt:Secret"]!;
        var jwtIssuer    = _config["Jwt:Issuer"]!;
        var jwtAudience  = _config["Jwt:Audience"]!;
        var expiryMinutes = int.Parse(_config["Jwt:AccessTokenExpiryMinutes"]!);

        var key   = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtSecret));
        var creds = new SigningCredentials(key, SecurityAlgorithms.HmacSha256);

        var claims = new List<Claim>
        {
            new(JwtRegisteredClaimNames.Sub,  user.UserID.ToString()),
            new(JwtRegisteredClaimNames.Jti,  Guid.NewGuid().ToString()),
            new(JwtRegisteredClaimNames.Email, user.Email),
            new("fullName", user.FullName)
        };

        // Thêm từng role làm Claim riêng
        claims.AddRange(roles.Select(r => new Claim(ClaimTypes.Role, r)));

        var token = new JwtSecurityToken(
            issuer:   jwtIssuer,
            audience: jwtAudience,
            claims:   claims,
            expires:  DateTime.UtcNow.AddMinutes(expiryMinutes),
            signingCredentials: creds);

        var accessToken   = new JwtSecurityTokenHandler().WriteToken(token);
        var refreshToken  = Convert.ToBase64String(Guid.NewGuid().ToByteArray());  // Simplified

        return new AuthResponse(accessToken, "Bearer", expiryMinutes * 60, refreshToken);
    }
}
