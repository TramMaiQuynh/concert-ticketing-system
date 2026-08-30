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
    decimal Amount);

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
