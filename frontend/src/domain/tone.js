import {
  ConcertStatus, BookingStatus, InventoryStatus, QueueEntryStatus,
  WaitlistEntryStatus, RefundStatus, PaymentStatus, TicketStatus,
} from './enums';

/**
 * Ánh xạ trạng thái nghiệp vụ → sắc thái hiển thị.
 *
 * Tách khỏi enums.js có chủ đích: enums.js là bản sao NGUYÊN VĂN miền giá trị của
 * database và không được lẫn chuyện trình bày. File này là tầng hiển thị, và là
 * nơi DUY NHẤT quyết định "Confirmed thì màu gì".
 *
 * Không có nó thì mỗi trang tự chọn màu, và cùng một trạng thái sẽ xanh ở trang
 * này, xám ở trang kia — người dùng mất luôn khả năng quét nhanh bằng màu.
 *
 * Quy ước sắc thái:
 *   green  = đang tốt, đã xong xuôi
 *   amber  = đang chờ, cần người dùng làm gì đó
 *   red    = đã hủy, đã hỏng, không dùng được nữa
 *   blue   = đang diễn tiến, hệ thống đang xử lý
 *   violet = đang giữ cho một luồng khác (danh sách chờ)
 *   neutral= trung tính, không đáng chú ý
 */

export const CONCERT_TONE = {
  [ConcertStatus.Draft]:      'neutral',
  [ConcertStatus.Published]:  'blue',
  [ConcertStatus.OnSale]:     'green',
  [ConcertStatus.SaleClosed]: 'neutral',
  [ConcertStatus.Completed]:  'neutral',
  [ConcertStatus.Cancelled]:  'red',
};

export const BOOKING_TONE = {
  [BookingStatus.Pending]:   'amber',
  [BookingStatus.Confirmed]: 'green',
  [BookingStatus.Expired]:   'neutral',
  [BookingStatus.Cancelled]: 'red',
};

export const SEAT_TONE = {
  [InventoryStatus.Available]:         'neutral',
  [InventoryStatus.OnHold]:            'amber',
  [InventoryStatus.OnHoldForWaitlist]: 'violet',
  [InventoryStatus.Booked]:            'red',
  [InventoryStatus.Unavailable]:       'neutral',
};

export const QUEUE_TONE = {
  [QueueEntryStatus.Waiting]:   'amber',
  [QueueEntryStatus.Admitted]:  'green',
  [QueueEntryStatus.Expired]:   'neutral',
  [QueueEntryStatus.Exited]:    'neutral',
  [QueueEntryStatus.Cancelled]: 'red',
};

export const WAITLIST_TONE = {
  [WaitlistEntryStatus.Active]:    'blue',
  [WaitlistEntryStatus.Granted]:   'green',
  [WaitlistEntryStatus.Expired]:   'neutral',
  [WaitlistEntryStatus.Fulfilled]: 'green',
  [WaitlistEntryStatus.Cancelled]: 'red',
};

export const REFUND_TONE = {
  [RefundStatus.Pending]:   'amber',
  [RefundStatus.Confirmed]: 'green',
  [RefundStatus.Failed]:    'red',
  [RefundStatus.Cancelled]: 'neutral',
};

export const PAYMENT_TONE = {
  [PaymentStatus.Pending]:            'amber',
  [PaymentStatus.Confirmed]:          'green',
  [PaymentStatus.Failed]:             'red',
  [PaymentStatus.PartiallyRefunded]:  'violet',
  [PaymentStatus.Refunded]:           'neutral',
};

export const TICKET_TONE = {
  [TicketStatus.Issued]:    'green',
  [TicketStatus.Used]:      'neutral',
  [TicketStatus.Cancelled]: 'red',
};

/** Kết quả soát vé — chỉ SUCCESS là xanh, mọi kết quả khác đều là từ chối. */
export function checkinTone(result) {
  return result === 'SUCCESS' ? 'green' : 'red';
}

/**
 * Màu bìa sự kiện, sinh từ ID.
 *
 * Hệ thống không có ảnh bìa (database không lưu ảnh), nhưng một lưới thẻ toàn ô
 * xám thì không phân biệt được sự kiện nào với sự kiện nào. Sinh màu từ ID cho
 * mỗi sự kiện một danh tính thị giác ổn định — cùng một ID luôn ra cùng một màu,
 * qua mọi lần tải và mọi thiết bị.
 *
 * Bước nhảy màu dùng GÓC VÀNG 137.5°, không phải một số nhỏ tuỳ ý.
 *
 * Bản trước nhân ID với 47, và kết quả thực tế cho thấy nó hỏng đúng ở chỗ quan
 * trọng nhất: ba sự kiện ID 1, 2, 3 ra hue 47°, 94°, 141° — cả ba đều nằm trong
 * dải vàng-lục, nhìn gần như nhau. Mà ID liền kề chính là các sự kiện đứng cạnh
 * nhau trên trang chủ, tức là trường hợp cần phân biệt nhất.
 *
 * Góc vàng là lời giải kinh điển cho bài toán này (cùng nguyên lý xếp hạt hướng
 * dương): mọi dãy liên tiếp đều được rải đều quanh vòng màu, không bao giờ dồn
 * cục. Với ID 1, 2, 3 ta được 137°, 275°, 52° — lục, tím, cam.
 *
 * Hai màu trong dải lệch nhau 32° để có chiều sâu, và khoá độ bão hoà / độ sáng
 * để không bao giờ ra màu chói hay đục.
 */
export function coverGradient(id) {
  const hue = (Number(id) * 137.508) % 360;
  return `linear-gradient(135deg,
    hsl(${hue.toFixed(1)} 64% 52%) 0%,
    hsl(${((hue + 32) % 360).toFixed(1)} 58% 42%) 100%)`;
}

/**
 * Nhãn ngắn hiện trong ô ghế.
 *
 * Mã ghế thật KHÔNG ngắn như 'A1'. Dữ liệu chạy thật cho ra 'STD-023955-1' —
 * gồm tiền tố hạng vé và số hiệu đợt tạo. Nhồi nguyên chuỗi đó vào ô tròn 40px
 * làm chữ tràn ra ngoài và cả sơ đồ trông như hỏng.
 *
 * Lấy đoạn cuối sau dấu phân cách: 'STD-023955-1' → '1', 'A1' → 'A1'. Mã đầy đủ
 * vẫn nằm trong tooltip và nhãn cho trình đọc màn hình, nên không mất thông tin.
 */
export function seatShortLabel(code) {
  const raw = String(code ?? '').trim();
  if (!raw) return '';
  const parts = raw.split(/[-_\s/.]+/).filter(Boolean);
  const last = parts[parts.length - 1] ?? raw;
  return last.length <= 4 ? last : last.slice(-3);
}
