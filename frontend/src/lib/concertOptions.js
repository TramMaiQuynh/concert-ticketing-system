import { useState, useEffect } from 'react';
import api from '../api/client';
import { useCatalog } from './localCatalog';

/**
 * Nguồn danh sách concert cho các ô chọn trong khu quản trị.
 *
 * VÌ SAO GOM VÀO MỘT CHỖ
 * ----------------------
 * Trang quản trị có tới bảy khối cần chọn concert (sửa concert, chuyển trạng thái,
 * hạng vé, kho ghế, hàng đợi, danh sách chờ, khoá ghế) và ba trang cùng cần
 * (Concert, Khuyến mãi, Người dùng). Nếu mỗi khối tự gọi `GET /concerts` thì chỉ
 * riêng việc mở trang đã bắn ra bảy request giống hệt nhau — vô ích và làm nhiễu
 * cả log máy chủ lẫn tab Network khi cần chẩn đoán.
 *
 * Ở đây giữ MỘT promise dùng chung: ai hỏi trước thì gọi mạng, những người hỏi sau
 * dùng lại đúng kết quả đó.
 *
 * DANH SÁCH NÀY KHÔNG ĐẦY ĐỦ, và điều đó là cố ý phải nói rõ: `GET /concerts` lọc
 * bỏ concert Draft (`ConcertStatus <> 'Draft'`), mà concert luôn sinh ra ở Draft.
 * Nên nó được TRỘN với sổ tay cục bộ — nơi giữ ID của những concert vừa tạo trong
 * phiên làm việc này. Kể cả vậy vẫn có thể thiếu, nên ô nhập ID thủ công luôn còn đó.
 */

let cache = null;      // kết quả đã lấy được
let inflight = null;   // lời gọi đang bay, để không bắn trùng

function fetchConcerts() {
  if (cache) return Promise.resolve(cache);
  if (!inflight) {
    inflight = api
      .get('/concerts', { params: { page: 1, pageSize: 100 } })
      .then((res) => {
        cache = Array.isArray(res.data) ? res.data : [];
        return cache;
      })
      .catch(() => {
        // Lỗi tải gợi ý không được chặn thao tác quản trị: người dùng vẫn nhập ID tay.
        cache = [];
        return cache;
      })
      .finally(() => { inflight = null; });
  }
  return inflight;
}

/** Buộc lấy lại ở lần hỏi kế tiếp — gọi sau khi vừa tạo hoặc đổi trạng thái concert. */
export function invalidateConcerts() {
  cache = null;
}

/**
 * @returns {{options: Array<{id:number,name:string}>, remember: Function, reload: Function}}
 */
export function useConcertOptions() {
  const local = useCatalog('concert');
  const [remote, setRemote] = useState(cache ?? []);

  useEffect(() => {
    let alive = true;
    fetchConcerts().then((list) => { if (alive) setRemote(list); });
    return () => { alive = false; };
  }, []);

  const options = [...local.items];
  remote.forEach((c) => {
    if (!options.some((m) => m.id === c.concertID)) {
      options.push({ id: c.concertID, name: c.concertName });
    }
  });

  const reload = () => {
    invalidateConcerts();
    fetchConcerts().then(setRemote);
  };

  return { options, remember: local.remember, reload };
}
