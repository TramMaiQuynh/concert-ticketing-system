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
    /// Sơ đồ chỗ ngồi: hình học địa điểm + khu + ghế (FR11a). MỘT contract duy nhất cho
    /// cả venue Zone/Seat cũ và venue StagePass (VenueTemplate/ConcertMapRevision) —
    /// chọn nguồn theo việc Concert có ConcertMapRevision đang Locked hay không (xem
    /// implementation). Trả về null khi concert không tồn tại hoặc không còn bán vé.
    /// </summary>
    Task<SeatMapDto?> GetSeatMapAsync(int concertId);

    /// <summary>
    /// Chi tiet ghe cua MOT khu (FR11a — muc hai cua so do), cung nguon-kep voi
    /// GetSeatMapAsync. Tra null khi concert khong con ban ve hoac khu khong thuoc dia
    /// diem cua concert.
    /// </summary>
    Task<SeatMapZoneDetailDto?> GetSeatMapZoneAsync(int concertId, int zoneId);

    /// <summary>Khuyến mãi đang trong hiệu lực của concert (VW_ActivePromotions), công khai như GetByIdAsync.</summary>
    Task<IEnumerable<ActivePromotion>> ListActivePromotionsAsync(int concertId);
}

public interface ICheckInRepository
{
    Task<CheckInResponse> CheckInAsync(int staffUserId, CheckInRequest request);

    /// <summary>Xem trước vé thuộc về ai trước khi xác nhận check-in — không đổi trạng thái vé.</summary>
    Task<CheckInPreview?> PreviewAsync(CheckInRequest request);
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
    Task<IEnumerable<AdminConcertListItem>> ListConcertsAsync(AdminCatalogQuery query);
    Task<IEnumerable<ConcertArtistListItem>> ListConcertArtistsAsync(int concertId);
    Task<IEnumerable<AdminZoneListItem>> ListZonesAsync(AdminCatalogQuery query);
    Task<IEnumerable<AdminSeatListItem>> ListSeatsAsync(AdminCatalogQuery query);
    Task<IEnumerable<AdminCategoryListItem>> ListCategoriesAsync(AdminCatalogQuery query);
    Task<IEnumerable<AdminPromotionListItem>> ListPromotionsAsync(AdminCatalogQuery query);
    Task<IEnumerable<AdminDiscountCodeListItem>> ListDiscountCodesAsync(AdminCatalogQuery query);
    Task<IEnumerable<AdminRefundListItem>> ListRefundsAsync(AdminCatalogQuery query);
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
    Task CreateSeatsBatchAsync(int actorUserId, int zoneId, CreateSeatsBatchRequest request);
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

    // Cau hinh Fair Access / Waitlist theo tung Concert (FR64a, BR43, BR45b, BR47b)
    Task ConfigureQueueAsync(int actorUserId, int concertId, ConfigureQueueRequest request);
    Task ConfigureWaitlistAsync(int actorUserId, int concertId, ConfigureWaitlistRequest request);

    // Vong doi khuyen mai / ma giam gia (FR52, FR53b)
    Task UpdatePromotionStatusAsync(int actorUserId, int promotionId, string status);
    Task UpdateDiscountCodeStatusAsync(int actorUserId, int discountCodeId, string status);

    // ── StagePass (D.2/D.4/D.5): VenueTemplate studio + ConcertMap ──────────
    Task<IEnumerable<VenueTemplateListItem>> ListVenueTemplatesAsync(int venueId, bool includeArchived);
    Task<int> CreateVenueTemplateAsync(int actorUserId, int venueId, CreateVenueTemplateRequest request);
    Task UpdateVenueTemplateAsync(int actorUserId, int venueTemplateId, UpdateVenueTemplateRequest request);
    Task<IEnumerable<VenueTemplateVersionListItem>> ListVenueTemplateVersionsAsync(int venueTemplateId);
    Task<IEnumerable<ConcertPublishedTemplateVersionItem>> ListPublishedTemplateVersionsForConcertAsync(int actorUserId, int concertId);
    Task<int> CreateVenueTemplateVersionAsync(int actorUserId, int venueTemplateId, CreateVenueTemplateVersionRequest request);
    Task<VenueTemplateVersionDetail?> GetVenueTemplateVersionDetailAsync(int venueTemplateVersionId);
    Task PublishVenueTemplateVersionAsync(int actorUserId, int venueTemplateVersionId);
    Task DeleteVenueTemplateVersionDraftAsync(int actorUserId, int venueTemplateVersionId);
    Task<int> ConfigureTemplateFloorAsync(int actorUserId, int venueTemplateVersionId, ConfigureTemplateFloorRequest request);
    Task DeleteTemplateFloorAsync(int actorUserId, int templateFloorId);
    Task<int> ConfigureTemplateObjectAsync(int actorUserId, int templateFloorId, ConfigureTemplateObjectRequest request);
    Task DeleteTemplateObjectAsync(int actorUserId, int templateObjectId);
    Task<int> ConfigureTemplateSectionAsync(int actorUserId, int templateFloorId, ConfigureTemplateSectionRequest request);
    Task DeleteTemplateSectionAsync(int actorUserId, int templateSectionId);
    Task<int> ConfigureTemplateSeatAsync(int actorUserId, int templateSectionId, ConfigureTemplateSeatRequest request);
    Task DeleteTemplateSeatAsync(int actorUserId, int templateSeatId);

    Task<ConcertMapDto?> GetConcertMapAsync(int actorUserId, int concertId);
    Task<int> CreateConcertMapAsync(int actorUserId, int concertId);
    Task<IEnumerable<ConcertMapRevisionListItem>> ListConcertMapRevisionsAsync(int actorUserId, int concertMapId);
    Task<int> CreateConcertMapRevisionAsync(int actorUserId, int concertMapId, CreateConcertMapRevisionRequest request);
    Task LockConcertMapRevisionAsync(int actorUserId, int concertMapRevisionId);

    /// <summary>
    /// Huỷ một ConcertMapRevision đang Draft để mở lại được Draft khác. Không có
    /// đường này thì một lần snapshot nhầm là ngõ cụt vĩnh viễn trong ứng dụng:
    /// không huỷ được Draft, không tạo được Draft mới (60217), mà Lock thì không
    /// thay thế được revision Locked (60236/60219).
    /// </summary>
    Task CancelConcertMapRevisionDraftAsync(int actorUserId, int concertMapRevisionId);

    /// <summary>Cây Floor→Section→Seat đầy đủ của một revision — kể cả ghế CHƯA vào kho vé (EventSeatID null), để Admin duyệt trước khi thêm.</summary>
    Task<ConcertMapRevisionDetail?> GetConcertMapRevisionDetailAsync(int actorUserId, int concertMapRevisionId);

    /// <summary>Cầu nối ConcertMapRevisionSeat ↔ EventSeat (sp_AddEventSeatsFromMapRevision). Trả số ghế đã thêm.</summary>
    Task<int> AddEventSeatsFromMapRevisionAsync(int actorUserId, int concertMapRevisionId, AddEventSeatsFromMapRevisionRequest request);
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
