using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Domain.Models;

namespace ConcertTicketing.Application.Interfaces;

// ── Repository Interfaces (định nghĩa trong Application, implement trong Infrastructure) ──

public interface IUserRepository
{
    Task<UserAccount?> GetByUsernameAsync(string username);
    Task<UserAccount?> GetByIdAsync(int userId);
    Task<IEnumerable<string>> GetRolesAsync(int userId);
    Task<int> CreateAsync(UserAccount user, string passwordHash);

    // ── Refresh Token (lưu trong DB, không phải Redis) ──────────────────────
    // Trả về raw token để gửi cho client qua HttpOnly Cookie.
    // DB chỉ lưu SHA-256 hash của token.
    Task<string> CreateRefreshTokenAsync(int userId, DateTime expiryUtc);
    Task<(int UserId, bool IsValid)> ValidateRefreshTokenAsync(string rawToken);
    Task RevokeRefreshTokenAsync(string rawToken);
}

public interface IBookingRepository
{
    Task<CreateBookingResponse> CreateAsync(int customerUserId, CreateBookingRequest request);
    Task<BookingDetail?> GetByIdAsync(int bookingId, int customerUserId);
    Task CancelAsync(int bookingId, int customerUserId);
    Task ApplyPromotionAsync(int bookingId, int customerUserId, string discountCode);
}

public interface IConcertRepository
{
    Task<IEnumerable<ConcertListItem>> GetListAsync(int page, int pageSize, string? status);
    Task<ConcertDetail?> GetByIdAsync(int concertId);
    Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId);
}

public interface ICheckInRepository
{
    Task<CheckInResponse> CheckInAsync(int staffUserId, CheckInRequest request);
}

public interface IPaymentRepository
{
    Task<InitiatePaymentResponse> InitiateAsync(int bookingId, int customerUserId);
    Task ConfirmAsync(int bookingId, int paymentId, string? providerReference); // gọi sp_ConfirmPayment
    Task<int> ProcessRefundAsync(int paymentId, decimal refundAmount, string reason, int actorUserId); // gọi sp_ProcessRefund
}
