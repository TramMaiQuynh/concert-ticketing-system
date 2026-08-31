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
    Task ConfirmAsync(int bookingId, int paymentId, string? signature, string? providerReference); // gọi sp_ConfirmPayment (xác thực chữ ký)
    Task<int> ProcessRefundAsync(int paymentId, decimal refundAmount, string reason, int actorUserId); // gọi sp_ProcessRefund
}

// ── Admin / Organizer management ──────────────────────────────────────────────

public interface IAdminRepository
{
    Task<int> CreateConcertAsync(int actorUserId, CreateConcertRequest request);
    Task UpdateConcertAsync(int concertId, int actorUserId, UpdateConcertRequest request);
    Task UpdateConcertStatusAsync(int concertId, int actorUserId, string status);
    Task<int> CreateVenueAsync(int actorUserId, CreateVenueRequest request);
    Task<int> CreateZoneAsync(int actorUserId, int venueId, CreateZoneRequest request);
    Task<int> CreateSeatAsync(int actorUserId, int zoneId, CreateSeatRequest request);
    Task<int> ConfigureTicketCategoryAsync(int actorUserId, int concertId, ConfigureTicketCategoryRequest request);
    Task AddEventSeatsAsync(int actorUserId, int concertId, AddEventSeatsRequest request);
    Task<int> CreatePromotionAsync(int actorUserId, int concertId, CreatePromotionRequest request);
    Task AssignRoleAsync(int actorUserId, AssignRoleRequest request);

    // Admin/Organizer extended management (BP3/BP9/BP12/BP13)
    Task<int> CreateDiscountCodeAsync(int actorUserId, int promotionId, CreateDiscountCodeRequest request);
    Task SetEventSeatUnavailableAsync(int actorUserId, int eventSeatId, SetEventSeatUnavailableRequest request);
    Task UpdateUserStatusAsync(int actorUserId, int targetUserId, UpdateUserStatusRequest request);
    Task AddCheckinStaffAssignmentAsync(int actorUserId, AddCheckinStaffAssignmentRequest request);
}

// ── Waitlist ──────────────────────────────────────────────────────────────────

public interface IWaitlistRepository
{
    Task<WaitlistJoinResponse> JoinAsync(int customerUserId, int concertId);
    Task<WaitlistEntryStatusDto?> GetMyEntryAsync(int customerUserId, int concertId);
}

// ── Fair Access Queue (BP11 / FR64) ───────────────────────────────────────────

public interface IQueueRepository
{
    Task<JoinQueueResponse> JoinAsync(int customerUserId, int concertId);
    Task<QueueEntryStatusDto?> GetMyEntryAsync(int customerUserId, int concertId);
}
