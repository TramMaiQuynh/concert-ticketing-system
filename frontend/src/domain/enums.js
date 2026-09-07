/**
 * Các tập giá trị trạng thái, sao chép NGUYÊN VĂN từ §18.4.1 của database_plan
 * và từ CHECK constraint tương ứng trong database.
 *
 * Đây là file tồn tại vì một lý do cụ thể: bản frontend trước so sánh trạng thái bằng
 * chuỗi tự chế rải rác trong JSX — `seat.inventoryStatus === 'Sold'`,
 * `seat.inventoryStatus === 'Held'`, `c.concertStatus === 'On Sale'`. Không giá trị nào
 * trong số đó tồn tại trong hệ thống: miền thật là Booked / OnHold / OnSale (không dấu
 * cách). Hậu quả là ghế đã bán vẫn hiển thị như ghế trống, và không concert nào từng
 * được tô màu "đang mở bán". Kiểu lỗi này không bao giờ nổ ra — nó chỉ âm thầm hiển thị
 * sai — nên phải chặn bằng cách chỉ có MỘT nơi định nghĩa chuỗi trạng thái.
 */

// ── Concert Status (§18.4.1) ────────────────────────────────────────────────
export const ConcertStatus = {
  Draft: 'Draft',
  Published: 'Published',
  OnSale: 'OnSale',
  SaleClosed: 'SaleClosed',
  Completed: 'Completed',
  Cancelled: 'Cancelled',
};

/** Nhãn tiếng Việt cho người dùng cuối. */
export const CONCERT_STATUS_LABEL = {
  [ConcertStatus.Draft]: 'Bản nháp',
  [ConcertStatus.Published]: 'Sắp mở bán',
  [ConcertStatus.OnSale]: 'Đang mở bán',
  [ConcertStatus.SaleClosed]: 'Đã đóng bán',
  [ConcertStatus.Completed]: 'Đã diễn ra',
  [ConcertStatus.Cancelled]: 'Đã hủy',
};

/**
 * Chỉ trạng thái OnSale mới đặt vé được — sp_CreateBooking kiểm tra đúng điều này
 * (THROW 51001) và còn đòi SalesPaused = 0.
 */
export function canPurchase(concert) {
  return concert?.concertStatus === ConcertStatus.OnSale && concert?.salesPaused === false;
}

// ── EventSeat Inventory Status (§18.4.1) ────────────────────────────────────
export const InventoryStatus = {
  Available: 'Available',
  OnHold: 'OnHold',
  OnHoldForWaitlist: 'OnHoldForWaitlist',
  Booked: 'Booked',
  Unavailable: 'Unavailable',
};

/** Trạng thái giả, CHỈ có ở giao diện: ghế người dùng đang chọn. Không thuộc miền
 *  InventoryStatus của database, nên đặt tên khác hẳn để không bị nhầm là giá trị thật. */
export const SELECTED_PSEUDO_STATUS = 'Selected';

/**
 * Chú giải sơ đồ ghế. PHẢI liệt kê đủ CẢ NĂM giá trị của InventoryStatus, cộng một
 * trạng thái giả 'Selected' thuần giao diện (ghế người dùng đang chọn, chưa gửi lên
 * máy chủ).
 *
 * Bản trước thiếu 'OnHoldForWaitlist' — chính là kiểu lỗi mà file này sinh ra để ngăn:
 * ghế đang giữ cho danh sách chờ vẫn được tô màu nhưng không có dòng chú giải nào,
 * người dùng không hiểu ô màu đó nghĩa là gì. Danh sách này là nguồn DUY NHẤT của chú
 * giải; đừng dựng lại một danh sách khác trong trang.
 */
export const SEAT_LEGEND = [
  { status: InventoryStatus.Available, label: 'Còn trống' },
  { status: SELECTED_PSEUDO_STATUS, label: 'Đang chọn' },
  { status: InventoryStatus.OnHold, label: 'Đang được giữ' },
  { status: InventoryStatus.OnHoldForWaitlist, label: 'Giữ cho danh sách chờ' },
  { status: InventoryStatus.Booked, label: 'Đã bán' },
  { status: InventoryStatus.Unavailable, label: 'Không sử dụng' },
];

/** Ghế chỉ chọn được khi đang Available — đúng điều kiện của sp_CreateBooking (CI04). */
export function isSeatSelectable(seat) {
  return seat?.inventoryStatus === InventoryStatus.Available;
}

// ── Booking Status (§18.4.1) ────────────────────────────────────────────────
export const BookingStatus = {
  Pending: 'Pending',
  Confirmed: 'Confirmed',
  Expired: 'Expired',
  Cancelled: 'Cancelled',
};

export const BOOKING_STATUS_LABEL = {
  [BookingStatus.Pending]: 'Chờ thanh toán',
  [BookingStatus.Confirmed]: 'Đã xác nhận',
  [BookingStatus.Expired]: 'Đã hết hạn giữ chỗ',
  [BookingStatus.Cancelled]: 'Đã hủy',
};

// ── Queue Entry Status (§18.4.1) ────────────────────────────────────────────
export const QueueEntryStatus = {
  Waiting: 'Waiting',
  Admitted: 'Admitted',
  Expired: 'Expired',
  Exited: 'Exited',
  Cancelled: 'Cancelled',
};

export const QUEUE_STATUS_LABEL = {
  [QueueEntryStatus.Waiting]: 'Đang xếp hàng',
  [QueueEntryStatus.Admitted]: 'Đã được vào mua vé',
  [QueueEntryStatus.Expired]: 'Hết hạn lượt mua',
  [QueueEntryStatus.Exited]: 'Đã rời hàng đợi',
  [QueueEntryStatus.Cancelled]: 'Đã bị hủy',
};

// ── Waitlist Entry Status (§18.4.1) ─────────────────────────────────────────
export const WaitlistEntryStatus = {
  Active: 'Active',
  Granted: 'Granted',
  Expired: 'Expired',
  Fulfilled: 'Fulfilled',
  Cancelled: 'Cancelled',
};

export const WAITLIST_STATUS_LABEL = {
  [WaitlistEntryStatus.Active]: 'Đang chờ',
  [WaitlistEntryStatus.Granted]: 'Đã được cấp cơ hội mua',
  [WaitlistEntryStatus.Expired]: 'Cơ hội đã hết hạn',
  [WaitlistEntryStatus.Fulfilled]: 'Đã dùng cơ hội',
  [WaitlistEntryStatus.Cancelled]: 'Đã hủy',
};

// ── Kết quả xác nhận thanh toán (PaymentConfirmOutcome ở backend) ───────────
/**
 * KHÔNG chỉ có "thành công / thất bại": sp_ConfirmPayment vẫn COMMIT thành công trong
 * ba tình huống bất thường và tạo yêu cầu hoàn tiền, còn đơn hàng thì KHÔNG được xác
 * nhận. Giao diện phải phân biệt được, nếu không sẽ báo "thanh toán thành công" cho
 * khách trong khi khách không hề có vé.
 */
export const PaymentOutcome = {
  Confirmed: 'Confirmed',
  AlreadyConfirmed: 'AlreadyConfirmed',
  AlreadyRefunded: 'AlreadyRefunded',
  AutoRefundedAmountMismatch: 'AutoRefundedAmountMismatch',
  AutoRefundedDuplicatePayment: 'AutoRefundedDuplicatePayment',
  AutoRefundedBookingNotPending: 'AutoRefundedBookingNotPending',
};

// ── Vai trò (bảng Role — dữ liệu nền §23.7) ─────────────────────────────────
export const Role = {
  Admin: 'Admin',
  Organizer: 'Organizer',
  Customer: 'Customer',
  /** Chú ý dấu gạch nối và khoảng trắng: khớp đúng RoleName trong DB. */
  CheckInStaff: 'Check-in Staff',
};

// ── Kết quả check-in (sp_CheckInTicket trả qua @ValidationResult) ───────────
export const CHECKIN_RESULT_LABEL = {
  SUCCESS: 'Hợp lệ — đã cho vào',
  INVALID: 'Mã vé không tồn tại',
  WRONG_EVENT: 'Vé không thuộc concert này',
  ALREADY_USED: 'Vé đã được sử dụng',
  CANCELLED: 'Vé đã bị hủy',
  INVALID_STATUS: 'Vé không ở trạng thái hợp lệ',
  UNAUTHORIZED: 'Bạn không được phân công cho concert này',
  DUPLICATE_CHECKIN: 'Vé đã được check-in trước đó',
  FAILED: 'Không xác thực được vé',
};

// ═══════════════════════════════════════════════════════════════════════════
// MIỀN GIÁ TRỊ CHO KHU QUẢN TRỊ
//
// Mọi tập dưới đây chép đúng từ CHECK constraint tương ứng trong database, đọc
// trực tiếp từ `sys.check_constraints` chứ không chép tay từ tài liệu. Form quản
// trị chỉ được chào đúng những giá trị này: sai một chữ là stored procedure ném
// lỗi, và người dùng cuối không có cách nào đoán ra giá trị đúng.
// ═══════════════════════════════════════════════════════════════════════════

/** CHK_Artist_Status */
export const ArtistStatus = { Active: 'Active', Retired: 'Retired' };
/** CHK_Venue_Status */
/** CHK_Role_Status — §12.3.2: cho biết vai trò có đang được phép PHÂN CÔNG hay
 *  không. Đóng lại KHÔNG thu hồi quyền của người đang giữ vai trò. */
export const RoleStatus = { Active: 'Active', Inactive: 'Inactive' };
export const VenueStatus = { Active: 'Active', Inactive: 'Inactive' };
/** CHK_Zone_Status */
export const ZoneStatus = { Active: 'Active', Retired: 'Retired' };
/** CHK_Seat_Status */
export const SeatStatus = { Active: 'Active', Retired: 'Retired' };
/** CHK_Category_Status */
export const CategoryStatus = { Active: 'Active', Inactive: 'Inactive' };
/** CHK_Promotion_Status */
export const PromotionStatus = { Draft: 'Draft', Active: 'Active', Disabled: 'Disabled' };
/** CHK_DiscountCode_Status */
export const DiscountCodeStatus = { Active: 'Active', Disabled: 'Disabled' };
/** CHK_Queue_Status */
export const QueueStatus = { Open: 'Open', Closed: 'Closed' };
/** CHK_Waitlist_Status */
export const WaitlistStatus = { Open: 'Open', Closed: 'Closed' };
/** CHK_Queue_Policy và CHK_Waitlist_Policy dùng chung hai giá trị này. */
export const AccessPolicy = { FIFO: 'FIFO', RANDOM: 'RANDOM' };
/** CHK_UserAccount_Status */
export const UserStatus = { Active: 'Active', Locked: 'Locked', Disabled: 'Disabled' };
/** CHK_StaffAssignment_Status */
export const AssignmentStatus = { Active: 'Active', Revoked: 'Revoked' };
/** CHK_Refund_Status */
export const RefundStatus = {
  Pending: 'Pending', Confirmed: 'Confirmed', Failed: 'Failed', Cancelled: 'Cancelled',
};

/**
 * CHK_Promotion_DiscountType.
 * Chú ý 'Fixed Amount' CÓ dấu cách — đây đúng là giá trị database lưu, không phải
 * nhãn hiển thị. Gửi 'FIXED' hay 'FixedAmount' đều bị CHECK constraint từ chối.
 */
export const DiscountType = { Percentage: 'Percentage', FixedAmount: 'Fixed Amount' };

export const DISCOUNT_TYPE_LABEL = {
  [DiscountType.Percentage]: 'Theo phần trăm (%)',
  [DiscountType.FixedAmount]: 'Số tiền cố định (₫)',
};

/** Grant/Revoke của sp_AssignRole — không phải trạng thái, là hành động. */
export const RoleAction = { Grant: 'Grant', Revoke: 'Revoke' };

/** Nhãn tiếng Việt dùng chung cho các trạng thái quản trị. */
export const ADMIN_STATUS_LABEL = {
  Active: 'Đang hoạt động',
  Inactive: 'Ngừng dùng',
  Retired: 'Đã ngừng',
  Disabled: 'Đã tắt',
  Locked: 'Bị khóa',
  Draft: 'Bản nháp',
  Open: 'Đang mở',
  Closed: 'Đã đóng',
  Revoked: 'Đã thu hồi',
  Pending: 'Chờ xử lý',
  Confirmed: 'Đã xác nhận',
  Failed: 'Thất bại',
  Cancelled: 'Đã hủy',
  FIFO: 'FIFO — ai vào trước phục vụ trước',
  RANDOM: 'RANDOM — bốc ngẫu nhiên',
  Grant: 'Cấp quyền',
  Revoke: 'Thu hồi quyền',
};

/**
 * Vai trò có thể gán qua sp_AssignRole. Phải khớp CHÍNH XÁC cột Role.RoleName
 * trong database — bao gồm dấu gạch nối và khoảng trắng của 'Check-in Staff'.
 */
export const ASSIGNABLE_ROLES = [Role.Admin, Role.Organizer, Role.Customer, Role.CheckInStaff];
