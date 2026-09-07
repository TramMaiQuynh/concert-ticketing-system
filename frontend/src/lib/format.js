/**
 * Định dạng hiển thị.
 *
 * TIỀN TỆ: hệ thống chỉ dùng VND. Đây không phải lựa chọn giao diện mà là ràng buộc
 * của database: Payment.Currency là CHAR(3) với `CHK_Payment_Currency CHECK (Currency
 * = 'VND')`, và mọi cột tiền đều là DECIMAL(18,0) — nghĩa là KHÔNG có phần thập phân,
 * đơn vị nhỏ nhất là 1 đồng (§23.7: "toàn bộ DECIMAL(18,0) VND, không lưu tỷ giá/đa
 * tiền tệ"). Bản trước hiển thị "$1,000,000" — sai đơn vị tới bốn chữ số về mặt cảm
 * nhận giá và không có cơ sở nào trong dữ liệu.
 */

const vnd = new Intl.NumberFormat('vi-VN', {
  style: 'currency',
  currency: 'VND',
  maximumFractionDigits: 0,
});

/** Số tiền VND. Trả về '—' cho null/undefined để không in ra "NaN ₫". */
export function formatMoney(amount) {
  if (amount === null || amount === undefined || Number.isNaN(Number(amount))) return '—';
  return vnd.format(Number(amount));
}

/**
 * Mốc ngày giờ đầy đủ.
 *
 * Dùng formatToParts rồi tự ghép, thay vì để Intl tự sắp xếp: mẫu mặc định của
 * vi-VN đặt GIỜ LÊN TRƯỚC ("02:39 Thứ 3, 06/10/2026"), điều này đã thấy khi chạy
 * thật. Với một trang bán vé thì NGÀY mới là thứ người ta quét mắt tìm trước,
 * giờ chỉ là chi tiết phụ — nên thứ tự đúng phải là "Thứ 3, 06/10/2026 · 02:39".
 */
const dateTimeParts = new Intl.DateTimeFormat('vi-VN', {
  weekday: 'short',
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hour12: false,
});

const dateOnly = new Intl.DateTimeFormat('vi-VN', {
  weekday: 'short',
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
});

export function formatDateTime(value) {
  const d = toDate(value);
  if (!d) return '—';
  const p = Object.fromEntries(
    dateTimeParts.formatToParts(d).map((x) => [x.type, x.value]),
  );
  return `${p.weekday}, ${p.day}/${p.month}/${p.year} · ${p.hour}:${p.minute}`;
}

export function formatDate(value) {
  const d = toDate(value);
  return d ? dateOnly.format(d) : '—';
}

/**
 * QUY ƯỚC MÚI GIỜ — đã kiểm chứng trên chính database, không suy đoán:
 *
 * Toàn bộ mốc thời gian nghiệp vụ dùng `SYSDATETIME()`, tức GIỜ CỦA MÁY CHỦ SQL, chứ
 * không phải UTC. Điều này đúng cho cả 40 stored procedure lẫn mọi DEFAULT của bảng
 * (Booking.CreatedTimestamp, QueueEntry.JoinedTimestamp, CheckIn.CheckInTimestamp…);
 * không có chỗ nào dùng SYSUTCDATETIME(). Quan trọng là nó NHẤT QUÁN: sp_ReleaseExpiredHolds
 * và sp_ConfirmPayment cũng so sánh bằng SYSDATETIME(), nên hạn giữ chỗ được đánh giá
 * đúng ở phía máy chủ.
 *
 * Cột DATETIME2 không mang thông tin múi giờ, nên .NET tuần tự hóa thành chuỗi KHÔNG có
 * hậu tố (ví dụ "2026-10-05T16:31:50.4046209") — đã xác nhận bằng một lời gọi thật tới
 * GET /api/concerts. JavaScript diễn giải chuỗi dạng đó theo giờ địa phương, tức là khớp
 * với ý nghĩa của dữ liệu. Vì vậy KHÔNG được tự gắn thêm 'Z': làm vậy sẽ diễn giải giờ
 * máy chủ như giờ UTC và lệch đúng bằng offset của trình duyệt (ở Việt Nam là 7 tiếng),
 * đủ để đồng hồ đếm ngược giữ chỗ sai hoàn toàn.
 *
 * Vẫn giữ nhánh tôn trọng hậu tố có sẵn: một vài giá trị do tầng ứng dụng sinh ra
 * (CheckInResponse.CheckInTime lấy từ DateTime.UtcNow) được tuần tự hóa KÈM 'Z', và
 * JavaScript xử lý đúng những chuỗi đó một cách tự nhiên.
 *
 * GIỚI HẠN cần biết: cách này đúng khi trình duyệt và máy chủ SQL cùng múi giờ — phù hợp
 * với phạm vi triển khai một instance đã chốt ở §23.7. Nếu về sau phục vụ nhiều múi giờ
 * thì phải chuyển tầng database sang lưu UTC, không thể vá ở frontend.
 */
export function toDate(value) {
  if (!value) return null;
  if (value instanceof Date) return Number.isNaN(value.getTime()) ? null : value;

  const d = new Date(String(value));
  return Number.isNaN(d.getTime()) ? null : d;
}

/** Số mili-giây còn lại tới mốc thời gian (âm nếu đã qua). */
export function msUntil(value) {
  const d = toDate(value);
  return d ? d.getTime() - Date.now() : 0;
}

/** mm:ss cho đồng hồ đếm ngược; kẹp ở 00:00 thay vì hiện số âm. */
export function formatCountdown(ms) {
  const clamped = Math.max(0, ms);
  const totalSeconds = Math.floor(clamped / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

/**
 * Chuyển giá trị của <input type="datetime-local"> thành chuỗi gửi lên API.
 *
 * Ô datetime-local cho ra dạng "2026-09-06T19:00" — KHÔNG kèm múi giờ. Đó đúng là
 * thứ cần gửi: cột DATETIME2 của database không mang múi giờ và mọi mốc nghiệp vụ
 * dùng SYSDATETIME() (giờ máy chủ). Nếu ở đây đổi sang ISO có hậu tố 'Z' (ví dụ
 * bằng new Date(v).toISOString()) thì giờ người dùng gõ sẽ bị lệch đúng bằng offset
 * trình duyệt — ở Việt Nam là 7 tiếng — và một concert đặt lúc 19:00 sẽ vào database
 * thành 12:00. Vì vậy hàm này CỐ Ý không đụng gì tới chuỗi.
 *
 * Trả về null cho ô để trống, để trường tùy chọn gửi lên đúng nghĩa "không đặt".
 */
export function toApiDateTime(value) {
  const v = (value ?? '').trim();
  return v === '' ? null : v;
}

/** Ngược lại: đổ giá trị từ API vào ô datetime-local (cắt phần giây/mili). */
export function toInputDateTime(value) {
  const d = toDate(value);
  if (!d) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
       + `T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/**
 * Mã đơn hàng mà khách nhìn thấy: BKG-000180.
 *
 * Backend dựng chuỗi này bằng $"BKG-{BookingID:D6}" và trả trong BookingDetail
 * (bookingReference), nhưng danh sách lịch sử đặt vé đọc qua
 * VW_CustomerBookingHistory thì KHÔNG có trường đó. Trang "Vé của tôi" vì vậy từng
 * gọi cùng một đơn là "#180" trong khi trang thanh toán gọi nó là "BKG-000180" —
 * khách nhớ mã ở màn này rồi tìm không ra ở màn kia. Định dạng chỉ là cách trình
 * bày của BookingID nên dựng lại ở đây là đúng chỗ, miễn là giữ y hệt công thức.
 */
export function bookingReference(bookingId) {
  const n = Number(bookingId);
  return Number.isFinite(n) ? `BKG-${String(n).padStart(6, '0')}` : '';
}
