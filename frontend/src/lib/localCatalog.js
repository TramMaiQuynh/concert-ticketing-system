import { useCallback, useEffect, useState } from 'react';

/**
 * SỔ TAY CỤC BỘ CHO KHU QUẢN TRỊ
 *
 * VÌ SAO PHẢI CÓ FILE NÀY
 * -----------------------
 * Backend có 23 endpoint quản trị và **không có endpoint GET nào**. Không có
 * `GET /admin/venues`, `GET /admin/artists`, `GET /admin/users`, `GET /refunds`…
 * Khi tạo một Venue, máy chủ trả về đúng `{ "id": 12 }` rồi thôi — không có cách
 * nào hỏi lại danh sách Venue đã tạo.
 *
 * Với riêng Concert cũng không cứu được: `GET /concerts` lọc `ConcertStatus <> 'Draft'`,
 * mà Concert luôn được tạo ở trạng thái Draft. Nghĩa là concert vừa tạo xong KHÔNG
 * xuất hiện ở bất kỳ endpoint đọc nào cho tới khi được chuyển sang Published.
 *
 * Hệ quả thực tế: nếu giao diện không tự ghi nhớ, người quản trị tạo xong một Zone
 * là mất dấu ID của nó, và không tạo được Seat trong Zone đó nữa — chuỗi thao tác
 * Venue → Zone → Seat → Concert → Category → EventSeat đứt ngay bước thứ hai.
 *
 * File này giữ lại những gì máy chủ vừa trả về, để các bước sau có cái mà chọn.
 *
 * GIỚI HẠN — phải nói thẳng với người dùng trên giao diện
 * -------------------------------------------------------
 * Đây KHÔNG phải nguồn sự thật. Nó nằm trong `localStorage` của đúng trình duyệt
 * này: đổi máy, đổi trình duyệt hay xoá dữ liệu site là mất. Nguồn sự thật vẫn là
 * database. Sổ tay này chỉ giải quyết đúng một việc — nhớ hộ những ID mà API không
 * cho hỏi lại. Vì vậy mọi ô chọn dùng nó đều đi kèm ô nhập ID thủ công, để người
 * dùng luôn có đường đi khi sổ tay trống.
 *
 * Cách chữa tận gốc nằm ở backend: bổ sung các endpoint đọc cho tài nguyên quản trị.
 * Khi có, chỉ cần thay `useCatalog` bằng lời gọi API là xong, phần còn lại giữ nguyên.
 */

const KEY = 'ct.admin.catalog.v1';

/** Số bản ghi giữ lại cho mỗi loại — đủ dùng, không phình localStorage. */
const MAX_PER_KIND = 50;

const EMPTY = {
  artist: [], venue: [], zone: [], seat: [],
  concert: [], category: [], promotion: [], discountCode: [], refund: [],
};

function read() {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return { ...EMPTY };
    const parsed = JSON.parse(raw);
    // Hợp nhất với EMPTY để phiên bản cũ thiếu khoá không làm hỏng giao diện.
    return { ...EMPTY, ...(parsed && typeof parsed === 'object' ? parsed : {}) };
  } catch {
    // localStorage có thể bị chặn (chế độ riêng tư) hoặc chứa JSON hỏng.
    // Trả về sổ rỗng thay vì để cả trang quản trị sập.
    return { ...EMPTY };
  }
}

function write(data) {
  try {
    localStorage.setItem(KEY, JSON.stringify(data));
  } catch {
    // Hết quota hoặc bị chặn — bỏ qua. Mất sổ tay không ảnh hưởng tính đúng đắn:
    // người dùng vẫn nhập ID thủ công được.
  }
}

/** Phát cho mọi hook đang gắn, để hai khối trên cùng một trang không lệch nhau. */
const listeners = new Set();
function broadcast(data) {
  listeners.forEach((fn) => fn(data));
}

/**
 * @param {string} kind một khoá của EMPTY, ví dụ 'venue'
 * @returns {{items: Array, remember: Function, forget: Function, clear: Function}}
 */
export function useCatalog(kind) {
  const [store, setStore] = useState(read);

  useEffect(() => {
    listeners.add(setStore);
    return () => { listeners.delete(setStore); };
  }, []);

  // Đồng bộ khi người dùng mở khu quản trị ở nhiều tab.
  useEffect(() => {
    const onStorage = (e) => { if (e.key === KEY) setStore(read()); };
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  const remember = useCallback((entry) => {
    const next = read();
    const list = next[kind] ?? [];
    // Ghi đè bản ghi cùng id thay vì tạo trùng: cập nhật xong tên mới phải hiện ra.
    const merged = [{ ...entry, at: Date.now() }, ...list.filter((x) => x.id !== entry.id)];
    next[kind] = merged.slice(0, MAX_PER_KIND);
    write(next);
    broadcast(next);
  }, [kind]);

  const forget = useCallback((id) => {
    const next = read();
    next[kind] = (next[kind] ?? []).filter((x) => x.id !== id);
    write(next);
    broadcast(next);
  }, [kind]);

  const clear = useCallback(() => {
    const next = read();
    next[kind] = [];
    write(next);
    broadcast(next);
  }, [kind]);

  return { items: store[kind] ?? [], remember, forget, clear };
}

/** Xoá sạch sổ tay — dùng cho nút "dọn sổ tay" ở trang quản trị. */
export function clearAllCatalog() {
  write({ ...EMPTY });
  broadcast({ ...EMPTY });
}
