/**
 * Quy tắc mã ghế + kế hoạch tạo ghế — MỘT nguồn sự thật cho CẢ HAI form:
 * "Tạo ghế" (một ghế) và "Tạo hàng loạt" (nhiều hàng một lúc).
 *
 * Hai form dùng chung đúng bộ trường Tiền tố / Hàng / Số, và form đơn lẻ chỉ là
 * trường hợp đặc biệt của form hàng loạt: một hàng và một số. Vì cùng dựng mã bằng
 * một hàm, hai form không thể sinh ra hai kiểu mã khác nhau.
 *
 * ── Quy tắc mã ──────────────────────────────────────────────────────────────
 *   tiền tố (giữ NGUYÊN hoa/thường như người dùng gõ) + '-' + hàng + số
 *       Vip + A + 1  ->  Vip-A1
 *       VIP + A + 1  ->  VIP-A1
 *   Tiền tố đã kết thúc bằng '-', '_' hoặc '.' thì KHÔNG thêm dấu nữa — gõ "VIP-"
 *   cũng ra "VIP-A1", không ra "VIP--A1". Khoảng trắng hai đầu tiền tố được cắt bỏ,
 *   nên " VIP " cũng ra "VIP-A1".
 *
 * ── Vì sao HÀNG bắt buộc phải có trong mã ──────────────────────────────────
 * Không phải chuyện thẩm mỹ. UQ_Seat_Zone_SeatCode là UNIQUE(ZoneID, SeatCode),
 * nên nếu mã chỉ gồm tiền tố + số thì "Vip1" ở hàng A và "Vip1" ở hàng B là TRÙNG
 * NHAU, và sp_CreateSeatsBatch từ chối NGUYÊN LÔ bằng lỗi 59827. Đo trực tiếp trên
 * database thật: một lô chứa Vip1 ở hai hàng khác nhau bị chặn 59827. Nghĩa là
 * thiếu hàng trong mã thì KHÔNG THỂ tạo nhiều hàng một lúc — quy tắc này là điều
 * kiện của tính năng, không phải lựa chọn.
 */
export const SEAT_CODE_SEPARATOR = '-';

/**
 * Giới hạn độ dài mã ghế. Con số này KHÔNG tự đặt ở đây: nó là hợp đồng của hai
 * tầng bên dưới — cột Seat.SeatCode là varchar(64) và CreateSeatValidator trong
 * Validators.cs chặn ở MaximumLength(64). Giao diện kiểm lại vì mã ở đây được
 * SINH RA chứ không gõ tay, nên không thể chặn bằng maxLength của ô nhập; nếu để
 * lọt thì người dùng nhận 400 "Mã ghế tối đa 64 ký tự" mà không biết ghế nào.
 */
export const SEAT_CODE_MAX = 64;

/**
 * Giới hạn số ghế mỗi lô. Đúng bằng giới hạn của sp_CreateSeatsBatch (lỗi 59826,
 * "Danh sách ghe phai co tu 1 den 3600 phan tu") — đo trên database thật: gửi
 * 4.000 phần tử bị chặn 59826, 600 phần tử chạy được.
 */
export const SEAT_BATCH_MAX = 3600;

// Tiền tố được trim() trước, nên dấu cách KHÔNG thể là ký tự cuối — chỉ ba dấu này.
const TRAILING_SEPARATORS = ['-', '_', '.'];
const LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

/**
 * Dựng mã ghế theo đúng một quy tắc, dùng cho cả hai form.
 * @returns {string}
 */
export function buildSeatCode(prefix, rowLabel, columnNumber) {
  const p = String(prefix ?? '').trim();
  const row = String(rowLabel ?? '').trim();
  const sep = p === '' || TRAILING_SEPARATORS.includes(p.slice(-1)) ? '' : SEAT_CODE_SEPARATOR;
  return `${p}${sep}${row}${columnNumber}`;
}

function lettersToNumber(text) {
  let value = 0;
  for (const ch of text.toUpperCase()) {
    const index = LETTERS.indexOf(ch);
    if (index < 0) return null;
    value = value * 26 + (index + 1);
  }
  return value;
}

function numberToLetters(value) {
  let text = '';
  let n = value;
  while (n > 0) {
    const rest = (n - 1) % 26;
    text = LETTERS[rest] + text;
    n = Math.floor((n - 1) / 26);
  }
  return text;
}

/** Một mục là một hàng ("A") hoặc một khoảng hàng ("A-H"). */
function expandRowItem(item) {
  const parts = item.split('-');
  if (parts.length === 1) return { rows: [item] };
  if (parts.length > 2) return { error: `"${item}": khoảng hàng chỉ có một dấu gạch.` };

  const [from, to] = parts;
  if (from === '' || to === '') return { error: `"${item}": khoảng hàng phải có đủ hai đầu.` };

  const isLetters = /^[A-Za-z]+$/.test(from) && /^[A-Za-z]+$/.test(to);
  const isNumbers = /^\d+$/.test(from) && /^\d+$/.test(to);

  if (isLetters && from.length === to.length) {
    const a = lettersToNumber(from);
    const b = lettersToNumber(to);
    if (a > b) return { error: `"${item}": hàng cuối phải ở sau hàng đầu.` };
    const rows = [];
    for (let v = a; v <= b; v++) rows.push(numberToLetters(v));
    return { rows };
  }
  if (isNumbers) {
    const a = Number(from);
    const b = Number(to);
    if (a > b) return { error: `"${item}": số cuối phải ở sau số đầu.` };
    const rows = [];
    for (let v = a; v <= b; v++) rows.push(String(v));
    return { rows };
  }
  return {
    error: `"${item}": khoảng hàng chỉ hỗ trợ chữ cái cùng độ dài (A-H, AA-AD) hoặc số (1-10).`,
  };
}

/**
 * Tách "Danh sách hàng": "A-H" | "A,B,D-H" | "A" | "A B".
 * Giữ nguyên thứ tự người dùng gõ và giữ nguyên cách viết hoa/thường. Bỏ mục trùng
 * vì trùng hàng nghĩa là trùng (hàng, số) -> lỗi 59828.
 * @returns {{rows: string[], error: string|null}}
 */
export function parseRowList(text) {
  const raw = String(text ?? '').trim();
  if (raw === '') return { rows: [], error: 'Nhập hàng cần tạo (ví dụ A hoặc A-H).' };

  const items = raw.split(/[\s,;]+/).filter((item) => item !== '');
  const rows = [];
  for (const item of items) {
    const expanded = expandRowItem(item);
    if (expanded.error) return { rows: [], error: expanded.error };
    for (const row of expanded.rows) {
      if (!rows.includes(row)) rows.push(row);
    }
  }
  if (rows.length === 0) return { rows: [], error: 'Nhập hàng cần tạo (ví dụ A hoặc A-H).' };
  return { rows, error: null };
}

/** Số ghế sẽ tạo = số hàng × số ghế mỗi hàng. */
export function seatBatchCount(rows, start, end) {
  const perRow = Number(end) - Number(start) + 1;
  return perRow > 0 ? rows.length * perRow : 0;
}

/** Ghế thứ i trong lô, xếp theo hàng trước rồi tới số — khớp thứ tự ghế gửi lên. */
export function seatBatchAt(rows, start, end, index) {
  const perRow = Number(end) - Number(start) + 1;
  return {
    rowLabel: rows[Math.floor(index / perRow)],
    columnNumber: Number(start) + (index % perRow),
  };
}
/**
 * Kế hoạch đầy đủ của một lần tạo ghế.
 *
 * `blocked` vừa quyết định nút có bấm được không, vừa là CÂU HIỆN RA cho người
 * dùng — nên nút không bao giờ xám mà không nói vì sao. `preview` để mắt người
 * kiểm được một lệnh tạo hàng nghìn bản ghi mà KHÔNG hoàn tác được (không có
 * đường xoá ghế; chỉ Retire được từng ghế một).
 *
 * Form đơn lẻ gọi hàm này với `singleSeat: true`, đúng MỘT hàng và MỘT số; form hàng
 * loạt gọi với danh sách hàng và khoảng số. Cùng một hàm, nên hai form không thể lệch
 * nhau — và `singleSeat` là thứ chặn form đơn lẻ nhận danh sách hàng (nếu không nó sẽ
 * xem trước nhiều ghế nhưng chỉ gửi lên một).
 *
 * @returns {{entries: Array, total: number, blocked: string|null, preview: string|null}}
 */
export function seatBatchPlan({ zoneId, prefix, rows, start, end, singleSeat = false }) {
  const parsed = parseRowList(rows);
  const code = String(prefix ?? '').trim();
  const hasStart = String(start ?? '').trim() !== '';
  const hasEnd = String(end ?? '').trim() !== '';
  const from = Number(start);
  const to = Number(end);

  let blocked = null;
  if (!zoneId) {
    blocked = 'Chọn "Khu vật lý" ở trên trước.';
  } else if (!code) {
    blocked = 'Nhập tiền tố mã ghế (ví dụ Vip).';
  } else if (parsed.error) {
    blocked = parsed.error;
  } else if (singleSeat && parsed.rows.length > 1) {
    // Form đơn lẻ chỉ gửi MỘT ghế (entries[0]), nên nếu ô "Hàng" nhận danh sách thì
    // dòng xem trước sẽ hứa nhiều ghế mà thực tế chỉ tạo một. Chặn ngay tại đây.
    blocked = `Ô "Hàng" chỉ nhận một hàng, nhưng "${String(rows).trim()}" là ${parsed.rows.length} hàng. `
      + 'Muốn nhiều hàng thì dùng khối "Tạo nhiều hàng ghế một lúc".';
  } else if (!hasStart || !Number.isInteger(from) || from < 1) {
    blocked = 'Số ghế phải là số nguyên từ 1 trở lên.';
  } else if (!hasEnd || !Number.isInteger(to) || to < from) {
    blocked = 'Đến số ghế phải là số nguyên lớn hơn hoặc bằng Từ số ghế.';
  } else if (seatBatchCount(parsed.rows, from, to) > SEAT_BATCH_MAX) {
    blocked = `${parsed.rows.length} hàng × ${to - from + 1} số = `
      + `${seatBatchCount(parsed.rows, from, to)} ghế, vượt mức tối đa ${SEAT_BATCH_MAX} ghế `
      + 'mỗi lần. Hãy chia thành nhiều lần.';
  }

  if (blocked) return { entries: [], total: 0, blocked, preview: null };

  const total = seatBatchCount(parsed.rows, from, to);
  const entries = Array.from({ length: total }, (_, i) => {
    const { rowLabel, columnNumber } = seatBatchAt(parsed.rows, from, to, i);
    const seatCode = buildSeatCode(code, rowLabel, columnNumber);
    return {
      seatCode,
      // Nhãn = CHÍNH mã ghế. SeatLabel là tên hiển thị của ghế, và với ghế sinh tự động
      // thì tên đúng là mã. sp_CreateSeatsBatch nhận seatLabel cho TỪNG ghế, còn
      // sp_CreateSeat nhận @SeatLabel — nên cả hai form đều lưu được nhãn.
      seatLabel: seatCode,
      seatRowLabel: rowLabel,
      seatColumnNumber: columnNumber,
    };
  });

  // Kiểm độ dài mã ở đây vì mã được SINH RA, không gõ tay — không chặn được bằng
  // maxLength. Để lọt thì máy chủ trả 400 "Mã ghế tối đa 64 ký tự" mà không nói
  // ghế nào trong lô, rất khó truy.
  const longest = entries.reduce((max, e) => (e.seatCode.length > max.length ? e.seatCode : max), '');
  if (longest.length > SEAT_CODE_MAX) {
    return {
      entries: [],
      total: 0,
      blocked: `Mã ghế dài nhất là "${longest}" (${longest.length} ký tự), vượt mức `
        + `${SEAT_CODE_MAX} ký tự. Rút ngắn tiền tố lại.`,
      preview: null,
    };
  }

  const first = entries[0];
  const last = entries[entries.length - 1];
  const rowCount = parsed.rows.length;
  const shape = rowCount === 1
    ? `hàng ${parsed.rows[0]}`
    : `${rowCount} hàng (${parsed.rows[0]}…${parsed.rows[rowCount - 1]})`;
  const preview = total === 1
    ? `Mã ghế sẽ tạo: ${first.seatCode}`
    : `Sẽ tạo ${total} ghế = ${shape} × ${to - from + 1} số · mã: ${first.seatCode} … ${last.seatCode}`;

  return { entries, total, blocked: null, preview };
}

