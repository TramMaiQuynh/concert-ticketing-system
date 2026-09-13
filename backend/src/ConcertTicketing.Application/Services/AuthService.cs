using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Text;
using Microsoft.Extensions.Configuration;
using Microsoft.IdentityModel.Tokens;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Domain.Models;

namespace ConcertTicketing.Application.Services;

/// <summary>
/// Sai tên đăng nhập hoặc mật khẩu (LoginAsync). Kiểu riêng thay vì ném thẳng
/// UnauthorizedAccessException: ErrorHandlingMiddleware cố tình thay MỌI
/// UnauthorizedAccessException bằng một câu chung "Bạn không có quyền thực hiện
/// thao tác này." — đúng cho các endpoint bị chặn quyền, nhưng vô hiệu hoá câu
/// message.Message đã được cân nhắc kỹ của LoginAsync ("Tên đăng nhập hoặc mật
/// khẩu không đúng.", cố tình GIỐNG HỆT nhau cho mọi lý do thất bại để không lộ
/// tên tài khoản có tồn tại hay không). Người dùng thật gõ sai mật khẩu vì vậy
/// luôn thấy một câu không liên quan gì đến việc đăng nhập. Kiểu con này được
/// middleware nhận diện riêng và trả đúng Message, mà không đụng tới hành vi ẩn
/// lý do của mọi UnauthorizedAccessException khác (token sai, chữ ký webhook sai).
/// </summary>
public class InvalidCredentialsException(string message) : UnauthorizedAccessException(message);

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
    /// <summary>
    /// Hash BCrypt của một mật khẩu ngẫu nhiên, chỉ dùng để tiêu tốn đúng lượng thời gian
    /// mà một lần xác thực thật tiêu tốn khi KHÔNG tìm thấy tài khoản.
    ///
    /// Không có nó, hai nhánh của LoginAsync chênh nhau khoảng một phần tư giây: tài khoản
    /// không tồn tại thì trả lời gần như tức thì, còn tài khoản có thật mà sai mật khẩu thì
    /// phải chờ BCrypt chạy với workFactor = 12 (~250ms). Chênh lệch cỡ đó đo được dễ dàng
    /// qua mạng, biến trang đăng nhập thành công cụ dò tên tài khoản hợp lệ — kể cả khi
    /// thông báo lỗi của hai nhánh giống hệt nhau.
    /// Cùng workFactor với lúc đăng ký để chi phí hai nhánh tương đương.
    /// </summary>
    private static readonly string DummyPasswordHash =
        BCrypt.Net.BCrypt.HashPassword(Guid.NewGuid().ToString("N"), workFactor: 12);

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
        var user = await _userRepository.GetByUsernameAsync(request.Username);

        // Luôn chạy một lần xác thực BCrypt, kể cả khi không tìm thấy tài khoản
        // (xem DummyPasswordHash): giữ cho hai nhánh có chi phí thời gian tương đương.
        // BCrypt.Verify đọc salt nhúng trong chuỗi hash ($2a$12$...) nên không cần cột
        // PasswordSalt riêng.
        var hashToCheck = user?.PasswordHash ?? DummyPasswordHash;
        var passwordOk = BCrypt.Net.BCrypt.Verify(request.Password, hashToCheck);

        // Thông báo giống hệt nhau cho mọi lý do thất bại: sai tên, sai mật khẩu, tài
        // khoản bị khóa, hay tài khoản dịch vụ không có mật khẩu.
        if (user is null || !passwordOk)
            throw new InvalidCredentialsException("Tên đăng nhập hoặc mật khẩu không đúng.");

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
        var validation = await _userRepository.ValidateRefreshTokenAsync(rawRefreshToken);

        // PHÁT HIỆN TOKEN BỊ DÙNG LẠI (OWASP — refresh token rotation).
        // Một token ĐÃ BỊ THU HỒI mà vẫn được trình lên nghĩa là có hai bản sao của cùng
        // một token đang tồn tại: bản hợp lệ đã được xoay vòng, và bản này. Không có cách
        // nào biết bản nào đang nằm trong tay kẻ tấn công, nên phản ứng đúng là cắt sạch
        // cả chuỗi token của user đó và buộc đăng nhập lại.
        //
        // Trước đây đoạn này chỉ từ chối riêng token bị trình lên. Comment cũ nói rằng hệ
        // thống "phát hiện" việc dùng lại, nhưng thực tế không hề: kẻ tấn công dùng token
        // ăn cắp trước sẽ tiếp tục giữ được chuỗi token hợp lệ, còn người dùng thật chỉ bị
        // đăng xuất — đúng chiều ngược lại với điều mong muốn.
        if (validation.State == RefreshTokenState.Revoked)
        {
            await _userRepository.RevokeAllRefreshTokensForUserAsync(validation.UserId);
            throw new UnauthorizedAccessException(
                "Phiên đăng nhập không còn hợp lệ. Vui lòng đăng nhập lại.");
        }

        if (!validation.IsValid || validation.UserId == 0)
            throw new UnauthorizedAccessException("Refresh token không hợp lệ hoặc đã hết hạn.");

        var userId = validation.UserId;

        // Thu hồi token cũ TRƯỚC khi cấp token mới (Refresh Token Rotation).
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
