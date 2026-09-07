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
    int? PurchaseLimit,
    // Hai cờ năng lực này là ĐIỀU KIỆN để client biết phải đi luồng nào.
    // FairAccessEnabled = true nghĩa là sp_CreateBooking sẽ từ chối (51007) nếu khách
    // chưa được admission từ Virtual Queue — không có thông tin này, giao diện chỉ có
    // thể phát hiện ra sau khi người dùng đã chọn ghế và bị chặn.
    bool FairAccessEnabled,
    bool WaitlistEnabled);

public record SeatDto(
    int SeatID,
    string SeatNumber,
    string? SectionName,
    string? Row,
    // TicketCategoryID là bắt buộc cho luồng Waitlist: JoinWaitlistRequest yêu cầu
    // @TicketCategoryId (BR40a — Waitlist gắn với MỘT hạng vé, không phải cả Concert),
    // trong khi trước đây client chỉ nhận được CategoryName. Không có ID này thì endpoint
    // /api/waitlist/concerts/{id}/join không thể gọi được từ giao diện.
    int TicketCategoryID,
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

/// <summary>
/// Một dòng trong lịch sử đặt vé của chính Customer (FR50), đọc từ
/// VW_CustomerBookingHistory. View này lọc theo SESSION_CONTEXT(N'UserID') nên chỉ
/// trả về dữ liệu của người đang đăng nhập.
/// </summary>
public record MyBookingListItem(
    int BookingID,
    int ConcertID,
    string ConcertName,
    string BookingStatus,
    DateTime CreatedTimestamp,
    DateTime? HoldExpiryDatetime,
    DateTime? ConfirmedTimestamp,
    DateTime? CancelledTimestamp,
    decimal SubtotalAmount,
    decimal FinalAmount,
    int SeatCount,
    string? PaymentStatus);

public record ApplyPromotionRequest(string DiscountCode);

// ── Payment ───────────────────────────────────────────────────────────────────

public record InitiatePaymentRequest();

// KHONG tra chu ky thanh toan cho client: chu ky la bi mat dung chung giua backend
// va cong thanh toan. Neu lo cho client, khach hang co the tu goi endpoint xac nhan
// va nhan ve ma khong tra tien.
public record InitiatePaymentResponse(
    int PaymentId,
    string PaymentUrl,
    string PaymentReference,
    decimal Amount);

/// <summary>Trạng thái của một refresh token khi được trình lên.</summary>
public enum RefreshTokenState
{
    /// <summary>Không tìm thấy token này trong hệ thống.</summary>
    NotFound,
    /// <summary>Token hợp lệ và còn hạn.</summary>
    Valid,
    /// <summary>Token tồn tại nhưng đã hết hạn.</summary>
    Expired,
    /// <summary>Token tồn tại nhưng ĐÃ BỊ THU HỒI — dấu hiệu token bị dùng lại (nghi đánh cắp).</summary>
    Revoked
}

/// <param name="UserId">Chủ sở hữu token (0 nếu không tìm thấy).</param>
public record RefreshTokenValidation(int UserId, RefreshTokenState State)
{
    public bool IsValid => State == RefreshTokenState.Valid;
}

/// <summary>
/// Ket qua nghiep vu cua mot lan xac nhan thanh toan (sp_ConfirmPayment.@Outcome).
///
/// Ton tai vi "khong nem exception" KHONG dong nghia voi "don hang da hoan tat":
/// khi so tien khong khop, khi Booking het han, hoac khi Booking da co Payment hieu
/// luc khac, SP ghi nhan tien da thu roi tao Refund va COMMIT thanh cong - don hang
/// KHONG duoc xac nhan. Neu API chi dua vao exception thi se bao voi cong thanh toan
/// va voi khach rang thanh toan thanh cong trong khi khach khong he co ve.
/// </summary>
public enum PaymentConfirmOutcome
{
    /// <summary>Da xac nhan Booking va phat hanh ve.</summary>
    Confirmed,
    /// <summary>Callback lap lai; Payment nay dang la Payment hieu luc cua Booking.</summary>
    AlreadyConfirmed,
    /// <summary>Callback lap lai; Payment nay truoc do da bi tu dong hoan tien.</summary>
    AlreadyRefunded,
    /// <summary>So tien khong khop tong don -> da tao yeu cau hoan tien.</summary>
    AutoRefundedAmountMismatch,
    /// <summary>Booking da co Payment hieu luc khac -> da tao yeu cau hoan tien.</summary>
    AutoRefundedDuplicatePayment,
    /// <summary>Booking het han hoac khong con cho thanh toan -> da tao yeu cau hoan tien.</summary>
    AutoRefundedBookingNotPending
}

/// <summary>Ket qua tra ve cho cong thanh toan sau khi xu ly callback.</summary>
/// <param name="Outcome">Ket qua nghiep vu.</param>
/// <param name="BookingConfirmed">Booking co thuc su duoc xac nhan hay khong.</param>
/// <param name="Message">Mo ta doc duoc cho nguoi van hanh.</param>
public record ConfirmPaymentResult(
    PaymentConfirmOutcome Outcome,
    bool BookingConfirmed,
    string Message);

/// <summary>
/// Than yeu cau huy/hoan tien. CHI co ly do.
///
/// KHONG co truong so tien, va do la co y: sp_ProcessRefund khong nhan tham so so tien
/// nao ca — no tu tinh @PaymentAmount * Concert.RefundPercentage / 100 (BR32a). Neu de
/// caller gui so tien len thi hoac gia tri do bi bo qua trong im lang, hoac no tro thanh
/// duong vuot mat chinh sach hoan tien cua Concert.
///
/// Truoc day record nay co truong RefundAmount va validator bat buoc no > 0, trong khi
/// ca hai endpoint deu chi doc Reason. Hau qua: moi request dung theo tai lieu (khong
/// gui so tien) deu bi tra ve HTTP 400 — toan bo quy trinh hoan tien khong goi duoc.
/// </summary>
public record RefundRequest(
    string? Reason);

/// <summary>
/// Kết thúc một yêu cầu hoàn tiền MÀ KHÔNG chi trả: Pending → Failed | Cancelled.
///
/// Failed    = cổng thanh toán từ chối / không chuyển được tiền về.
/// Cancelled = yêu cầu bị hủy hoặc bị từ chối trước khi xử lý xong (§10.1).
///
/// Reason là BẮT BUỘC: đây là thao tác đóng một yêu cầu hoàn tiền mà khách không
/// nhận được tiền, nên phải để lại dấu vết vì sao. Lý do đi vào AuditRecord chứ
/// không ghi đè Refund.RefundReason — cột đó giữ lý do KHÁCH được hoàn tiền.
/// Muốn xác nhận đã hoàn tiền xong thì dùng POST refunds/{id}/confirm.
/// </summary>
public record UpdateRefundStatusRequest(
    string Status,      // Failed | Cancelled
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
    DateTime? SaleStartDatetime = null,
    DateTime? SaleEndDatetime = null,
    int PurchaseLimit = 4,
    int? TemporaryHoldDuration = null,
    bool FairAccessEnabled = false,
    bool WaitlistEnabled = false,
    bool SalesPaused = false,
    string? CancellationPolicy = null,
    string? RefundPolicy = null,
    int? CancellationDeadlineHours = null,
    decimal? RefundPercentage = null);

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
    string? RefundPolicy = null,
    // BR31a/BR32a: dạng có cấu trúc của chính sách hủy/hoàn. sp_UpdateConcert đã nhận
    // hai tham số này từ đầu nhưng repository chưa truyền — nghĩa là hai cột cấu hình
    // chính sách không có đường cập nhật nào sau khi Concert được tạo.
    int? CancellationDeadlineHours = null,
    decimal? RefundPercentage = null);

public record UpdateConcertStatusRequest(string Status);

public record CreateVenueRequest(string VenueName, string? Address);

/// <summary>
/// Tao khu. Cac tham so hinh hoc deu tuy chon — dia diem chua khai bao so do van
/// tao khu binh thuong, giao dien tu rot ve che do liet ke theo nhom.
/// </summary>
public record CreateZoneRequest(
    string ZoneCode,
    string? ZoneName,
    // 'Seated' co ghe danh so | 'GeneralAdmission' ban theo suc chua, khong co ghe.
    string? ZoneType = null,
    int? ZoneLevel = null,          // tang/khan dai, 1 = tang tret
    int? ZoneX = null,
    int? ZoneY = null,
    int? ZoneWidth = null,
    int? ZoneHeight = null,
    decimal? ZoneRotation = null,   // do, de xoay khu huong ve san khau
    int? ZoneCapacity = null);      // CHI cho khu ve dung

public record CreateSeatRequest(
    string SeatCode,
    string? SeatLabel,
    // Vi tri trong khu. SeatCode la DINH DANH, hai truong nay moi la VI TRI.
    string? SeatRowLabel = null,
    int? SeatColumnNumber = null);

public record ConfigureTicketCategoryRequest(
    string CategoryName,
    string? CategoryDescription,
    decimal BasePrice,
    int? TicketCategoryId = null,
    // FR12: Active | Inactive. NULL = giữ nguyên khi cập nhật, 'Active' khi tạo mới.
    string? CategoryStatus = null);

public record AddEventSeatsRequest(int TicketCategoryId, List<int> SeatIds);

public record CreatePromotionRequest(
    string PromotionName,
    string? PromotionDescription,
    string DiscountType,
    decimal DiscountValue,
    DateTime StartDatetime,
    DateTime EndDatetime,
    int? UsageLimit = null,
    bool CodeRequiredFlag = false,
    // BR36b: gioi han so ghe duoc huong khuyen mai va gia tri giam toi da trong mot Booking.
    int? MaxApplicableQuantity = null,
    decimal? MaxDiscountAmount = null);

public record AssignRoleRequest(int TargetUserId, string RoleName, string GrantOrRevoke);

public record CreateArtistRequest(string ArtistName, string? ArtistDescription = null);

// Tham so NULL = giu nguyen gia tri hien tai. ArtistStatus: Active | Retired (BR50e).
public record UpdateArtistRequest(
    string? ArtistName = null,
    string? ArtistDescription = null,
    string? ArtistStatus = null);

public record IdResponse(int Id);

// ── Danh muc dung chung: Organizer DOC de chon khi tao concert (FR11a) ───────
//
// Dia diem va so do cua no do Admin dung mot lan; organizer cac lan sau chi chon
// lai. De chon duoc thi phai THAY duoc — do la muc dich cua nhung DTO nay.

/// <summary>
/// Mot dia diem trong danh muc, kem nhung gi organizer can de quyet dinh.
///
/// HasSeatMap la truong quan trong nhat o day: dia diem chua khai bao toa do van
/// ban ve binh thuong, nhung giao dien se rot ve che do liet ke theo khu thay vi
/// ve so do. Noi truoc dieu do luc chon con hon de organizer phat hien sau khi
/// da mo ban.
/// </summary>
public record VenueListItem(
    int VenueID,
    string VenueName,
    string? Address,
    string VenueStatus,
    bool HasSeatMap,
    int ZoneCount,
    int SeatCount,
    // Hinh hoc — de man quan tri ve duoc ban xem truoc. Go toa do ma khong nhin
    // thay ket qua thi khong ai sap dat duoc mot khan phong.
    int? MapWidth,
    int? MapHeight,
    int? StageX,
    int? StageY,
    int? StageWidth,
    int? StageHeight);

/// <summary>Mot khu trong danh muc dia diem — de organizer xem truoc bo cuc.</summary>
public record VenueZoneListItem(
    int ZoneID,
    string ZoneCode,
    string? ZoneName,
    string ZoneType,
    string ZoneStatus,
    int? ZoneLevel,
    int? ZoneCapacity,
    int SeatCount,
    int? ZoneX,
    int? ZoneY,
    int? ZoneWidth,
    int? ZoneHeight,
    decimal? ZoneRotation);

public record ArtistListItem(
    int ArtistID,
    string ArtistName,
    string? ArtistDescription,
    string ArtistStatus);

// ── So do cho ngoi (FR11a) ───────────────────────────────────────────────────
//
// Vi sao la mot endpoint rieng chu khong phai mo rong GET /concerts/{id}/seats:
// so do la mot TAI LIEU HINH HOC co cau truc long nhau (dia diem -> khu -> ghe),
// khong phai mot danh sach phang. Nhoi hinh hoc cua khu vao tung dong ghe se lap
// lai cung mot du lieu hang tram lan va van khong bieu dien duoc khu ve dung —
// loai khu KHONG co ghe nao.

public record SeatMapDto(
    int ConcertID,
    string VenueName,
    string? Address,
    int? MapWidth,
    int? MapHeight,
    int? StageX,
    int? StageY,
    int? StageWidth,
    int? StageHeight,
    List<SeatMapZoneDto> Zones);

/// <summary>
/// Mot khu o MUC TONG QUAN — chi hinh hoc va so lieu tong hop, KHONG co ghe.
///
/// Day la diem mau chot ve hieu nang. Do thuc te tren he thong nay: 234 byte moi
/// ghe. Tra ca ghe cua mot arena 20.000 cho la 4,5 MB moi lan mo trang; san van
/// dong 60.000 cho la 13 MB. Khong dung duoc.
///
/// Nguoi mua cung khong can tung ghe o buoc dau: ho chon KHU truoc (dua vao gia va
/// vi tri so voi san khau), roi moi chon ghe trong khu do. Dung hai muc vua khop
/// hanh vi that, vua giu payload buoc dau o vai KB du dia diem lon co nao.
/// </summary>
public record SeatMapZoneDto(
    int ZoneID,
    string ZoneCode,
    string? ZoneName,
    string ZoneType,
    int? ZoneLevel,
    int? ZoneX,
    int? ZoneY,
    int? ZoneWidth,
    int? ZoneHeight,
    decimal? ZoneRotation,
    int? ZoneCapacity,
    // Tong hop thay cho danh sach ghe.
    int SeatCount,
    int AvailableCount,
    decimal? MinPrice,
    decimal? MaxPrice);

/// <summary>Chi tiet mot khu: hinh hoc cua chinh no cong toan bo ghe ben trong.</summary>
public record SeatMapZoneDetailDto(
    int ZoneID,
    string ZoneCode,
    string? ZoneName,
    string ZoneType,
    int? ZoneLevel,
    int? ZoneX,
    int? ZoneY,
    int? ZoneWidth,
    int? ZoneHeight,
    decimal? ZoneRotation,
    int? ZoneCapacity,
    List<SeatMapSeatDto> Seats);

public record SeatMapSeatDto(
    int SeatID,              // EventSeatID — dung de dat ve
    string SeatNumber,       // ma ghe day du, dinh danh cho khach
    string? RowLabel,
    int? ColumnNumber,
    int TicketCategoryID,
    string CategoryName,
    string InventoryStatus,
    decimal Price);

// ── Waitlist ──────────────────────────────────────────────────────────────────

// BR40a: Waitlist gắn với một Ticket Category cụ thể, không phải cả Concert.
// BR40b: RequestedQuantity >= 1 — cơ hội chỉ được cấp khi đủ toàn bộ số ghế yêu cầu.
public record JoinWaitlistRequest(int TicketCategoryId, int RequestedQuantity = 1);

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
    DateTime? ValidToDatetime = null,
    // BR36c/BR36f: gioi han tong luot dung va luot dung cho moi khach hang.
    int? GlobalUsageLimit = null,
    int? PerCustomerUsageLimit = null);

public record SetEventSeatUnavailableRequest(
    bool Unavailable,
    string? Reason = null);

public record UpdateUserStatusRequest(string Status);

// BR39/FR51: AssignmentStatus 'Active' = phân công, 'Revoked' = thu hồi.
public record AddCheckinStaffAssignmentRequest(
    int StaffUserId,
    List<int> ConcertIds,
    string AssignmentStatus = "Active");

// ── Catalog lifecycle (FR59b / BR50e) ─────────────────────────────────────────
// Tham số NULL = giữ nguyên giá trị hiện tại.

public record UpdateVenueRequest(
    string? VenueName = null,
    string? Address = null,
    string? VenueStatus = null);        // Active | Inactive

public record UpdateZoneRequest(
    string? ZoneName = null,
    string? ZoneDescription = null,
    string? ZoneStatus = null,          // Active | Retired
    string? ZoneType = null,            // Seated | GeneralAdmission
    int? ZoneLevel = null,
    int? ZoneX = null,
    int? ZoneY = null,
    int? ZoneWidth = null,
    int? ZoneHeight = null,
    decimal? ZoneRotation = null,
    int? ZoneCapacity = null);

public record UpdateSeatRequest(
    string? SeatLabel = null,
    string? SeatStatus = null,          // Active | Retired
    string? SeatRowLabel = null,
    int? SeatColumnNumber = null);

/// <summary>
/// Khai bao mat phang toa do va vi tri san khau cua mot dia diem (FR11a).
///
/// Don vi la so nguyen TRU TUONG, khong phai met hay pixel: giao dien co gian
/// toan bo so do vao khung hinh dang co, nen cung mot so do dung duoc tren dien
/// thoai lan man hinh lon ma khong can du lieu do dac thuc dia.
///
/// San khau la DIEM TIEU CU — thu bien mot dam hinh chu nhat thanh so do co
/// nghia, vi khong co no thi khong noi duoc cho ngoi nao gan san khau hon.
/// </summary>
public record ConfigureVenueMapRequest(
    int? MapWidth = null,
    int? MapHeight = null,
    int? StageX = null,
    int? StageY = null,
    int? StageWidth = null,
    int? StageHeight = null);

// ── Fair Access / Waitlist configuration (FR64a, BR43, BR45b, BR47, BR47b) ────

public record ConfigureQueueRequest(
    int? AdmissionCapacity = null,
    string? FairAccessPolicy = null,            // FIFO | RANDOM
    int? AdmissionValiditySeconds = null,       // booking_ttl theo Concert
    bool InheritGlobalAdmissionValidity = false,
    string? QueueStatus = null);                // Open | Closed

public record ConfigureWaitlistRequest(
    string? AllocationPolicy = null,            // FIFO | RANDOM
    string? WaitlistStatus = null);             // Open | Closed

// ── Promotion lifecycle (FR52 / FR53b) ────────────────────────────────────────

// Dong hoac mo lai kha nang PHAN CONG cua mot Role (§12.3.2). Khong tac dong toi
// nguoi dang giu Role — thu hoi quyen cua mot nguoi cu the la viec cua
// POST /admin/roles/assign voi action = "Revoke".
public record UpdateRoleStatusRequest(string RoleName, string Status);   // Active | Inactive

public record UpdatePromotionStatusRequest(string Status);        // Draft | Active | Disabled

public record UpdateDiscountCodeStatusRequest(string Status);     // Active | Disabled

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
