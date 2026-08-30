using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.RateLimiting;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Services;

namespace ConcertTicketing.API.Controllers;

[ApiController]
[Route("api/auth")]
public class AuthController : ControllerBase
{
    private readonly IAuthService _authService;
    private readonly IConfiguration _configuration;

    // Tên cookie — ngắn để giảm bandwidth, không cần dễ đọc
    private const string RefreshTokenCookie = "rt";

    public AuthController(IAuthService authService, IConfiguration configuration)
    {
        _authService = authService;
        _configuration = configuration;
    }

    /// <summary>Đăng nhập — trả Access Token trong body, Refresh Token trong HttpOnly Cookie</summary>
    [HttpPost("login")]
    [AllowAnonymous]
    [EnableRateLimiting("auth")]  // 5 req/min — chống Brute Force
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Login([FromBody] LoginRequest request)
    {
        var (auth, rawRefreshToken) = await _authService.LoginAsync(request);
        SetRefreshTokenCookie(rawRefreshToken);
        return Ok(auth);
    }

    /// <summary>Đăng ký tài khoản mới</summary>
    [HttpPost("register")]
    [AllowAnonymous]
    [EnableRateLimiting("auth")]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> Register([FromBody] RegisterRequest request)
    {
        var (auth, rawRefreshToken) = await _authService.RegisterAsync(request);
        SetRefreshTokenCookie(rawRefreshToken);
        return StatusCode(StatusCodes.Status201Created, auth);
    }

    /// <summary>
    /// Cấp lại Access Token mới bằng Refresh Token (đọc từ HttpOnly Cookie).
    /// Thực hiện Refresh Token Rotation: token cũ bị revoke, token mới được cấp.
    /// </summary>
    [HttpPost("refresh")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(AuthResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    public async Task<IActionResult> Refresh()
    {
        // Đọc từ HttpOnly Cookie — không lấy từ request body
        // JavaScript không thể đọc cookie này (HttpOnly=true) → chống XSS
        var rawToken = Request.Cookies[RefreshTokenCookie];
        if (string.IsNullOrEmpty(rawToken))
            return Unauthorized("Refresh token không tồn tại.");

        var (auth, newRawToken) = await _authService.RefreshAsync(rawToken);
        SetRefreshTokenCookie(newRawToken);  // Ghi đè cookie với token mới
        return Ok(auth);
    }

    /// <summary>Đăng xuất — revoke Refresh Token trong DB và xóa Cookie</summary>
    [HttpPost("logout")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public async Task<IActionResult> Logout()
    {
        var rawToken = Request.Cookies[RefreshTokenCookie];
        if (!string.IsNullOrEmpty(rawToken))
            await _authService.LogoutAsync(rawToken);

        // Xóa cookie ngay cả khi không có token (đảm bảo client sạch)
        Response.Cookies.Delete(RefreshTokenCookie);
        return NoContent();
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private void SetRefreshTokenCookie(string rawRefreshToken)
    {
        var expiryDays = _configuration.GetValue<int>("Jwt:RefreshTokenExpiryDays", 7);
        Response.Cookies.Append(RefreshTokenCookie, rawRefreshToken, new CookieOptions
        {
            HttpOnly  = true,              // Không thể đọc bằng JavaScript → chống XSS
            Secure    = Request.IsHttps,   // Chỉ gửi qua HTTPS (tắt trong HTTP local dev)
            SameSite  = SameSiteMode.Strict, // Chống CSRF
            Expires   = DateTimeOffset.UtcNow.AddDays(expiryDays),
            Path      = "/api/auth"        // Cookie chỉ được gửi đến /api/auth/* (tối giản phạm vi)
        });
    }
}
