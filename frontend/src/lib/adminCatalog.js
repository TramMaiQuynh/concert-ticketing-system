import { useState, useEffect, useCallback } from 'react';
import api from '../api/client';

/**
 * DANH MỤC ĐỊA ĐIỂM VÀ NGHỆ SĨ — đọc từ máy chủ.
 *
 * Đây là thứ làm cho quyết định kiến trúc "Admin dựng sơ đồ địa điểm một lần,
 * các lần sau organizer chỉ việc chọn lại" trở thành một luồng dùng được thật.
 *
 * Trước đó ô chọn địa điểm đọc từ `localStorage` (lib/localCatalog.js) — sổ tay
 * chỉ chứa những gì CHÍNH trình duyệt đó vừa tạo. Hệ quả cụ thể: Admin dựng địa
 * điểm trên máy A, organizer mở máy B thì thấy danh sách RỖNG và phải được đọc
 * số hiệu địa điểm qua kênh khác. Vế "chỉ việc chọn" không tồn tại.
 *
 * Sổ tay cục bộ vẫn giữ nguyên vai trò cho những thực thể mà API KHÔNG có đường
 * đọc (khu, ghế, hạng vé, khuyến mãi, mã giảm giá).
 */

/* Bộ nhớ đệm cấp module: nhiều khối trên cùng một trang hỏi cùng một danh sách,
   và mỗi khối tự gọi mạng thì chỉ riêng việc mở trang đã bắn ra vài request
   giống hệt nhau. */
const cache = { venues: null, artists: null };
const inflight = { venues: null, artists: null };

function load(kind, path) {
  if (cache[kind]) return Promise.resolve(cache[kind]);
  if (!inflight[kind]) {
    inflight[kind] = api
      .get(path)
      .then((res) => {
        cache[kind] = Array.isArray(res.data) ? res.data : [];
        return cache[kind];
      })
      .catch(() => {
        // Lỗi tải danh mục không được chặn thao tác: mọi ô chọn đều kèm đường
        // nhập ID thủ công, nên người dùng vẫn đi tiếp được.
        cache[kind] = [];
        return cache[kind];
      })
      .finally(() => { inflight[kind] = null; });
  }
  return inflight[kind];
}

/** Buộc lấy lại ở lần hỏi kế tiếp — gọi sau khi vừa tạo địa điểm/nghệ sĩ mới. */
export function invalidateCatalog(kind) {
  if (kind) cache[kind] = null;
  else { cache.venues = null; cache.artists = null; }
}

/**
 * Danh sách địa điểm, đã chuyển sang dạng {id, name} mà IdPicker dùng.
 *
 * Nhãn cố tình kèm tình trạng sơ đồ. Địa điểm chưa khai báo toạ độ vẫn bán vé
 * bình thường, nhưng giao diện khách sẽ rơi về chế độ liệt kê theo khu thay vì
 * vẽ sơ đồ. Nói trước lúc chọn còn hơn để organizer phát hiện sau khi đã mở bán.
 */
export function useVenues() {
  const [raw, setRaw] = useState(cache.venues ?? []);
  const [loading, setLoading] = useState(!cache.venues);

  useEffect(() => {
    let alive = true;
    load('venues', '/admin/venues').then((list) => {
      if (alive) { setRaw(list); setLoading(false); }
    });
    return () => { alive = false; };
  }, []);

  const reload = useCallback(() => {
    invalidateCatalog('venues');
    load('venues', '/admin/venues').then(setRaw);
  }, []);

  const items = raw.map((v) => ({
    id: v.venueID,
    name: `${v.venueName}`
      + ` · ${v.hasSeatMap ? 'có sơ đồ' : 'CHƯA có sơ đồ'}`
      + (v.seatCount ? ` · ${v.seatCount} ghế` : ''),
    raw: v,
  }));

  return { items, raw, loading, reload };
}

export function useArtists() {
  const [raw, setRaw] = useState(cache.artists ?? []);
  const [loading, setLoading] = useState(!cache.artists);

  useEffect(() => {
    let alive = true;
    load('artists', '/admin/artists').then((list) => {
      if (alive) { setRaw(list); setLoading(false); }
    });
    return () => { alive = false; };
  }, []);

  const reload = useCallback(() => {
    invalidateCatalog('artists');
    load('artists', '/admin/artists').then(setRaw);
  }, []);

  const items = raw.map((a) => ({ id: a.artistID, name: a.artistName, raw: a }));

  return { items, raw, loading, reload };
}
