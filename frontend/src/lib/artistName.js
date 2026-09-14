/**
 * Đối chiếu tên nghệ sĩ để phát hiện bản ghi trùng.
 *
 * Vì sao cần lớp này: `sp_CreateArtist` cố ý KHÔNG đặt UNIQUE trên ArtistName — hai
 * nghệ sĩ khác nhau có thể trùng tên hợp lệ, và UNIQUE cũng không chặn được biến thể
 * dấu/khoảng trắng của cùng một tên. Chính SP ghi rõ việc chống trùng thuộc về "luồng
 * tìm-trước-khi-tạo ở tầng ứng dụng".
 *
 * Đặt ở `lib/` chứ không nhúng trong component để `npm test` kiểm được: đây là logic
 * thuần, và chính nó là thứ trước đây bị thiếu hoàn toàn.
 */

/** Chuẩn hoá để so "nhìn giống nhau": gộp khoảng trắng, không phân biệt hoa/thường và dấu. */
export function normalizeArtistName(value) {
  return String(value ?? '')
    .normalize('NFD')
    // Ở dạng NFD, dấu tiếng Việt là combining mark tách rời → bỏ hết.
    .replace(/[\u0300-\u036f]/g, '')
    // 'đ'/'Đ' là ký tự độc lập, NFD KHÔNG tách được, nên phải thay riêng.
    .replace(/[đĐ]/g, 'd')
    // Gộp mọi khoảng trắng liên tiếp thành một và bỏ khoảng trắng hai đầu, để
    // "  Sơn   Tùng " và "sơn tùng" được coi là cùng một tên.
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

/**
 * Các bản ghi trong `artists` có tên trùng với `typedName` sau khi chuẩn hoá.
 *
 * @param {string} typedName Tên người dùng đang gõ ở biểu mẫu tạo.
 * @param {Array<{artistID: number, artistName: string}>} artists Bản ghi thô từ API.
 * @returns {Array} Rỗng khi `typedName` rỗng — ô trống thì không cảnh báo gì.
 */
export function findSameNameArtists(typedName, artists) {
  const key = normalizeArtistName(typedName);
  if (!key) return [];
  return (artists ?? []).filter((a) => normalizeArtistName(a?.artistName) === key);
}