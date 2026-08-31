namespace ConcertTicketing.Application.DTOs;

// ── Auth ─────────────────────────────────────────────────────────────────────

public record LoginRequest(string Username, string Password);

public record RegisterRequest(
    string Username,
    string Email,
    string Password,
    string DisplayName);  // DB column: DisplayName

// RefreshToken KHÔNG trả trong body — được set qua HttpOnly Cookie
public record AuthResponse(
    string AccessToken,
    string TokenType,
    int ExpiresIn);     // seconds

// ── Concert ───────────────────────────────────────────────────────────────────

public record ConcertListItem(
    int ConcertID,
    string ConcertName,
    string ArtistName,
    string VenueName,
    string Address,
    DateTime StartDatetime,
    string ConcertStatus,
    bool SalesPaused,
    DateTime? SaleStartDatetime);

public record ConcertDetail(
    int ConcertID,
    string ConcertName,
    string ArtistName,
    string VenueName,
    string Address,
    DateTime StartDatetime,
    string ConcertStatus,
    bool SalesPaused,
    DateTime? SaleStartDatetime,
    DateTime? SaleEndDatetime,
    int? PurchaseLimit);

public record SeatDto(
    int SeatID,
    string SeatNumber,
    string? SectionName,
    string? Row,
    string CategoryName,
    string InventoryStatus,
    decimal Price);

// ── Booking ───────────────────────────────────────────────────────────────────

public record CreateBookingRequest(
    int ConcertId,
    List<int> SeatIds,
    int? WaitlistEntryId = null);

public record CreateBookingResponse(
    int BookingId,
    string BookingReference,
    DateTime HoldExpiryDatetime,
    decimal SubtotalAmount,
    decimal FinalAmount,
    string Status);

public record BookingDetail(
    int BookingID,
    int ConcertID,
    string ConcertName,
    string BookingStatus,
    DateTime CreatedTimestamp,
    DateTime? HoldExpiryDatetime,
    decimal SubtotalAmount,
    decimal DiscountAmount,
    decimal FinalAmount,
    string BookingReference,
    List<BookingAllocationDto> Seats);

public record BookingAllocationDto(
    int SeatID,
    string SeatNumber,
    string? SectionName,
    string CategoryName,
    decimal PriceAtBooking);

public record ApplyPromotionRequest(string DiscountCode);

// ── Payment ───────────────────────────────────────────────────────────────────

public record InitiatePaymentRequest();

public record InitiatePaymentResponse(
    int PaymentId,
    string PaymentUrl,
    string PaymentReference,
    decimal Amount,
    string PaymentSignature);

public record RefundRequest(
    decimal RefundAmount,
    string Reason);

// ── CheckIn ───────────────────────────────────────────────────────────────────

public record CheckInRequest(
    string TicketCode,
    int ConcertId);

public record CheckInResponse(
    string ValidationResult,   // SUCCESS / ALREADY_USED / INVALID / WRONG_CONCERT / ...
    string ValidationInfo,
    DateTime? CheckInTime);

// ── Pagination ────────────────────────────────────────────────────────────────

public record PagedResult<T>(
    IEnumerable<T> Items,
    int TotalCount,
    int Page,
    int PageSize)
{
    public int TotalPages => (int)Math.Ceiling((double)TotalCount / PageSize);
}

// ── Admin / Organizer management ──────────────────────────────────────────────

public record CreateConcertRequest(
    int ArtistId,
    int VenueId,
    string ConcertName,
    DateTime StartDatetime,
    DateTime EndDatetime,
    string? ConcertStatus = "Draft",
    DateTime? SaleStartDatetime = null,
    DateTime? SaleEndDatetime = null,
    int PurchaseLimit = 4,
    int? TemporaryHoldDuration = null,
    bool FairAccessEnabled = false,
    bool WaitlistEnabled = false,
    bool SalesPaused = false,
    string? CancellationPolicy = null,
    string? RefundPolicy = null);

public record UpdateConcertRequest(
    string? ConcertName = null,
    int? ArtistId = null,
    int? VenueId = null,
    DateTime? StartDatetime = null,
    DateTime? EndDatetime = null,
    DateTime? SaleStartDatetime = null,
    DateTime? SaleEndDatetime = null,
    int? PurchaseLimit = null,
    int? TemporaryHoldDuration = null,
    bool? FairAccessEnabled = null,
    bool? WaitlistEnabled = null,
    bool? SalesPaused = null,
    string? CancellationPolicy = null,
    string? RefundPolicy = null);

public record UpdateConcertStatusRequest(string Status);

public record CreateVenueRequest(string VenueName, string? Address);

public record CreateZoneRequest(string ZoneCode, string? ZoneName);

public record CreateSeatRequest(string SeatCode, string? SeatLabel);

public record ConfigureTicketCategoryRequest(string CategoryName, string? CategoryDescription);

public record AddEventSeatsRequest(int TicketCategoryId, decimal SalePrice, List<int> SeatIds);

public record CreatePromotionRequest(
    string PromotionName,
    string? PromotionDescription,
    string DiscountType,
    decimal DiscountValue,
    DateTime StartDatetime,
    DateTime EndDatetime,
    int? UsageLimit = null,
    bool CodeRequiredFlag = false);

public record AssignRoleRequest(int TargetUserId, string RoleName, string GrantOrRevoke);

public record IdResponse(int Id);

// ── Waitlist ──────────────────────────────────────────────────────────────────

public record WaitlistJoinResponse(int WaitlistEntryId, int QueuePosition);

public record WaitlistEntryStatusDto(
    int WaitlistEntryId,
    string EntryStatus,
    int QueuePosition,
    DateTime JoinedTimestamp,
    DateTime? OpportunityGrantedTimestamp,
    DateTime? OpportunityExpiryTimestamp);

// ── Admin / Organizer extended management ──────────────────────────────────────

public record CreateDiscountCodeRequest(
    string CodeValue,
    DateTime? ValidFromDatetime = null,
    DateTime? ValidToDatetime = null);

public record SetEventSeatUnavailableRequest(
    bool Unavailable,
    string? Reason = null);

public record UpdateUserStatusRequest(string Status);

public record AddCheckinStaffAssignmentRequest(int StaffUserId, List<int> ConcertIds);

// ── Fair Access Queue ─────────────────────────────────────────────────────────

public record JoinQueueResponse(
    int QueueEntryId,
    string QueueStatus,
    DateTime JoinedTimestamp);

public record QueueEntryStatusDto(
    int QueueEntryId,
    string QueueStatus,
    DateTime JoinedTimestamp,
    int? AdmissionPosition,
    DateTime? AdmissionExpiryTimestamp);
