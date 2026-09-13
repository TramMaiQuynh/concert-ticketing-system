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
    Task<RefreshTokenValidation> ValidateRefreshTokenAsync(string rawToken);
    Task RevokeRefreshTokenAsync(string rawToken);
    /// <summary>Thu hồi TOÀN BỘ refresh token của một user — dùng khi phát hiện token bị dùng lại.</summary>
    Task<int> RevokeAllRefreshTokensForUserAsync(int userId);
}

public interface IBookingRepository
{
    Task<CreateBookingResponse> CreateAsync(int customerUserId, CreateBookingRequest request);
    Task<BookingDetail?> GetByIdAsync(int bookingId, int customerUserId);
    /// <summary>Lịch sử đặt vé của chính Customer (FR50) — đọc VW_CustomerBookingHistory.</summary>
    Task<IEnumerable<MyBookingListItem>> GetMyBookingsAsync();
    Task CancelAsync(int bookingId, int customerUserId);
    Task ApplyPromotionAsync(int bookingId, int customerUserId, string discountCode);
}

public interface IConcertRepository
{
    Task<IEnumerable<ConcertListItem>> GetListAsync(int page, int pageSize, string? status);
    Task<ConcertDetail?> GetByIdAsync(int concertId);
    Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId);

    /// <summary>
    /// Sơ đồ chỗ ngồi: hình học địa điểm + khu + ghế (FR11a).
    /// Trả về null khi concert không tồn tại hoặc không còn bán vé.
    /// </summary>
    Task<SeatMapDto?> GetSeatMapAsync(int concertId);

    /// <summary>
    /// Chi tiet ghe cua MOT khu (FR11a — muc hai cua so do).
    /// Tra null khi concert khong con ban ve hoac khu khong thuoc dia diem cua concert.
    /// </summary>
    Task<SeatMapZoneDetailDto?> GetSeatMapZoneAsync(int concertId, int zoneId);
}

public interface ICheckInRepository
{
    Task<CheckInResponse> CheckInAsync(int staffUserId, CheckInRequest request);
}

public interface IPaymentRepository
{
    Task<InitiatePaymentResponse> InitiateAsync(int bookingId, int customerUserId);
    Task<ConfirmPaymentResult> ConfirmAsync(int bookingId, int paymentId, string? signature, string? providerReference); // sp_ConfirmPayment
    Task FailAsync(int bookingId, int paymentId, string? signature, string? providerReference);    // sp_FailPayment
    Task<int> ProcessRefundAsync(int bookingId, string? reason, int actorUserId, bool isConcertCancellation = false); // sp_ProcessRefund
    Task ConfirmRefundAsync(int refundId, int actorUserId);  // sp_ConfirmRefund
    Task UpdateRefundStatusAsync(int refundId, int actorUserId, string newStatus, string reason);  // sp_UpdateRefundStatus
}

// ── Admin / Organizer management ──────────────────────────────────────────────

public interface IAdminRepository
{
    // ── Doc danh muc — de Organizer chon dia diem/nghe si da co ──────────────
    Task<IEnumerable<VenueListItem>> ListVenuesAsync(bool includeInactive);
    Task<IEnumerable<VenueZoneListItem>> ListVenueZonesAsync(int venueId);
    Task<IEnumerable<ArtistListItem>> ListArtistsAsync(bool includeRetired);

    // ── Bao cao (FR55/FR56/BP14) — RLS qua SESSION_CONTEXT, khong nhan ActorUserID ──
    Task<ConcertSalesSummaryDto?> GetConcertSalesSummaryAsync(int concertId);
    Task<ConcertCheckInReportDto?> GetConcertCheckInReportAsync(int concertId);
    Task<IEnumerable<AttendeeListItem>> ListConcertAttendeesAsync(int concertId);

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

    // Danh muc Artist — du lieu dung chung giua moi Organizer nen CHI Admin (§12.6.1, BR50e)
    Task<int> CreateArtistAsync(int actorUserId, CreateArtistRequest request);
    Task UpdateArtistAsync(int actorUserId, int artistId, UpdateArtistRequest request);

    // Admin/Organizer extended management (BP3/BP9/BP12/BP13)
    Task<int> CreateDiscountCodeAsync(int actorUserId, int promotionId, CreateDiscountCodeRequest request);
    Task SetEventSeatUnavailableAsync(int actorUserId, int eventSeatId, SetEventSeatUnavailableRequest request);
    Task UpdateUserStatusAsync(int actorUserId, int targetUserId, UpdateUserStatusRequest request);
    Task AddCheckinStaffAssignmentAsync(int actorUserId, AddCheckinStaffAssignmentRequest request);
    Task<IEnumerable<WaitlistQueueItem>> ListConcertWaitlistAsync(int concertId);
    Task<IEnumerable<AuditRecordItem>> QueryAuditTrailAsync(AuditQueryRequest request);
    Task UpdateRoleStatusAsync(int actorUserId, string roleName, string status);

    // Vong doi du lieu danh muc (FR59b / BR50e): ngung su dung thay vi xoa vat ly.
    Task UpdateVenueAsync(int actorUserId, int venueId, UpdateVenueRequest request);
    Task UpdateZoneAsync(int actorUserId, int zoneId, UpdateZoneRequest request);
    Task UpdateSeatAsync(int actorUserId, int seatId, UpdateSeatRequest request);
    Task ConfigureVenueMapAsync(int actorUserId, int venueId, ConfigureVenueMapRequest request); // sp_ConfigureVenueMap

    // Cau hinh Fair Access / Waitlist theo tung Concert (FR64a, BR43, BR45b, BR47b)
    Task ConfigureQueueAsync(int actorUserId, int concertId, ConfigureQueueRequest request);
    Task ConfigureWaitlistAsync(int actorUserId, int concertId, ConfigureWaitlistRequest request);

    // Vong doi khuyen mai / ma giam gia (FR52, FR53b)
    Task UpdatePromotionStatusAsync(int actorUserId, int promotionId, string status);
    Task UpdateDiscountCodeStatusAsync(int actorUserId, int discountCodeId, string status);
}

// ── Waitlist ──────────────────────────────────────────────────────────────────

public interface IWaitlistRepository
{
    Task<WaitlistJoinResponse> JoinAsync(int customerUserId, int concertId, int ticketCategoryId, int requestedQuantity);
    Task<WaitlistEntryStatusDto?> GetMyEntryAsync(int customerUserId, int concertId);
}

// ── Fair Access Queue (BP11 / FR64) ───────────────────────────────────────────

public interface IQueueRepository
{
    Task<JoinQueueResponse> JoinAsync(int customerUserId, int concertId);
    Task<QueueEntryStatusDto?> GetMyEntryAsync(int customerUserId, int concertId);
    Task ExitAsync(int queueEntryId, int actorUserId);
}
