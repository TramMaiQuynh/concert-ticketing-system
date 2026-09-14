import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildSeatCode, parseRowList, seatBatchPlan, seatBatchCount, seatBatchAt,
  SEAT_BATCH_MAX, SEAT_CODE_MAX,
} from './seatCode.js';

// ── Quy tắc mã ──────────────────────────────────────────────────────────────
// Tiền tố giữ nguyên hoa/thường người dùng gõ; hệ thống tự thêm dấu gạch sau tiền tố.

test('mã = tiền tố + "-" + hàng + số, giữ nguyên hoa/thường như người gõ', () => {
  assert.equal(buildSeatCode('Vip', 'A', 1), 'Vip-A1');
  assert.equal(buildSeatCode('VIP', 'A', 1), 'VIP-A1');
  assert.equal(buildSeatCode('vip', 'A', 1), 'vip-A1');
  assert.equal(buildSeatCode('Vip', 'A', 12), 'Vip-A12');
});

test('tiền tố đã kết thúc bằng dấu thì KHÔNG thêm dấu nữa', () => {
  assert.equal(buildSeatCode('VIP-', 'A', 1), 'VIP-A1');
  assert.equal(buildSeatCode('VIP_', 'A', 1), 'VIP_A1');
  assert.equal(buildSeatCode('VIP.', 'A', 1), 'VIP.A1');
  // Khoảng trắng hai đầu bị cắt, nên "VIP " y như "VIP" — vẫn thêm dấu gạch.
  assert.equal(buildSeatCode('VIP ', 'A', 1), 'VIP-A1');
  assert.equal(buildSeatCode(' VIP ', 'A', 1), 'VIP-A1');
});

test('hàng nhiều ký tự và hàng số đều dựng được', () => {
  assert.equal(buildSeatCode('Vip', 'AA', 3), 'Vip-AA3');
  assert.equal(buildSeatCode('Vip', '10', 3), 'Vip-103');
});

// ── Tách "Danh sách hàng" ───────────────────────────────────────────────────

test('một hàng, một khoảng hàng, nhiều mục có khoảng trống', () => {
  assert.deepEqual(parseRowList('A').rows, ['A']);
  assert.deepEqual(parseRowList('A-H').rows, ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']);
  assert.deepEqual(parseRowList('A,C-H').rows, ['A', 'C', 'D', 'E', 'F', 'G', 'H']);
  assert.deepEqual(parseRowList('A B  D').rows, ['A', 'B', 'D']);
  assert.deepEqual(parseRowList('A,B,D-H').rows, ['A', 'B', 'D', 'E', 'F', 'G', 'H']);
});

test('hàng nhiều chữ cái cùng độ dài tăng đúng (AA-AD)', () => {
  // "Z-AB": hai đầu KHÁC độ dài nên không phải khoảng hàng — phải báo lỗi chứ không đoán bừa.
  assert.ok(parseRowList('Z-AB').error);
  assert.deepEqual(parseRowList('AA-AD').rows, ['AA', 'AB', 'AC', 'AD']);
});

test('hàng số cũng tách được', () => {
  assert.deepEqual(parseRowList('1-4').rows, ['1', '2', '3', '4']);
});

test('giữ nguyên thứ tự người dùng gõ và bỏ mục trùng', () => {
  assert.deepEqual(parseRowList('C,A,C').rows, ['C', 'A']);
  assert.deepEqual(parseRowList('H-A').error !== null, true);
});

test('danh sách hàng sai thì trả lỗi nói rõ, không ném ngoại lệ', () => {
  assert.ok(parseRowList('').error);
  assert.ok(parseRowList('   ').error);
  assert.match(parseRowList('A-').error, /đủ hai đầu/);
  assert.match(parseRowList('A-B-C').error, /một dấu gạch/);
  assert.match(parseRowList('A-3').error, /chữ cái cùng độ dài/);
  assert.match(parseRowList('D-A').error, /phải ở sau/);
  assert.deepEqual(parseRowList('A-').rows, []);
});

// ── Kế hoạch ────────────────────────────────────────────────────────────────

const base = { zoneId: '17', prefix: 'Vip', rows: 'A', start: '1', end: '1' };

test('form đơn lẻ = một hàng × một số → đúng MỘT ghế, mã Vip-A1', () => {
  const plan = seatBatchPlan(base);

  assert.equal(plan.blocked, null);
  assert.equal(plan.total, 1);
  assert.deepEqual(plan.entries, [
    { seatCode: 'Vip-A1', seatLabel: 'Vip-A1', seatRowLabel: 'A', seatColumnNumber: 1 },
  ]);
  assert.equal(plan.preview, 'Mã ghế sẽ tạo: Vip-A1');
});

test('NHÃN ghế = chính mã ghế, cho MỌI ghế trong lô', () => {
  // Nhãn ghế CHÍNH LÀ tiền tố + hàng + số, nên ghế sinh ra luôn có tên hiển thị.
  const plan = seatBatchPlan({ ...base, rows: 'A-C', end: '3' });

  assert.equal(plan.entries.length, 9);
  for (const entry of plan.entries) {
    assert.equal(entry.seatLabel, entry.seatCode, `${entry.seatCode} phải có nhãn bằng mã`);
  }
  assert.equal(plan.entries[0].seatLabel, 'Vip-A1');
  assert.equal(plan.entries.at(-1).seatLabel, 'Vip-C3');
});

test('singleSeat: form đơn lẻ TỪ CHỐI danh sách hàng, không hứa nhiều ghế', () => {
  // Không có luật này thì gõ "A-H" vào ô "Hàng" của form đơn lẻ sẽ hiện xem trước
  // "Sẽ tạo 8 ghế" nhưng handler chỉ gửi entries[0] — tức là tạo 1 ghế trong khi
  // giao diện nói 8.
  const plan = seatBatchPlan({ ...base, rows: 'A-H', singleSeat: true });

  assert.deepEqual(plan.entries, []);
  assert.match(plan.blocked, /chỉ nhận một hàng/);
  assert.match(plan.blocked, /"A-H" là 8 hàng/);

  // Vẫn nhận đúng một hàng.
  assert.equal(seatBatchPlan({ ...base, singleSeat: true }).blocked, null);
});

test('form hàng loạt: 8 hàng × 8 số = 64 ghế, mã có hàng', () => {
  const plan = seatBatchPlan({ ...base, rows: 'A-H', end: '8' });

  assert.equal(plan.blocked, null);
  assert.equal(plan.total, 64);
  assert.equal(plan.entries.length, 64);
  assert.equal(plan.entries[0].seatCode, 'Vip-A1');
  assert.equal(plan.entries[7].seatCode, 'Vip-A8');
  assert.equal(plan.entries[8].seatCode, 'Vip-B1');
  assert.equal(plan.entries.at(-1).seatCode, 'Vip-H8');
  assert.match(plan.preview, /Sẽ tạo 64 ghế/);
  assert.match(plan.preview, /8 hàng \(A…H\) × 8 số/);
  assert.match(plan.preview, /Vip-A1 … Vip-H8/);
});

test('HỒI QUY 59827: cùng tiền tố trên nhiều hàng phải sinh mã KHÁC NHAU', () => {
  // Đây là lỗi đã đo trên database thật: mã chỉ gồm tiền tố + số thì "Vip1" ở hàng A
  // và "Vip1" ở hàng B trùng nhau, và sp_CreateSeatsBatch từ chối NGUYÊN LÔ (59827).
  // Có hàng trong mã thì lô 26 hàng vẫn không có một mã nào lặp.
  const plan = seatBatchPlan({ ...base, rows: 'A-Z', end: '8' });

  const codes = plan.entries.map((e) => e.seatCode);
  assert.equal(codes.length, 26 * 8);
  assert.equal(new Set(codes).size, codes.length, 'không được có mã nào lặp');
  assert.equal(new Set(plan.entries.map((e) => `${e.seatRowLabel}|${e.seatColumnNumber}`)).size, codes.length);
});

test('thứ tự ghế: hàng trước, số sau — khớp thứ tự gửi lên', () => {
  assert.deepEqual(seatBatchAt(['A', 'B'], 1, 3, 0), { rowLabel: 'A', columnNumber: 1 });
  assert.deepEqual(seatBatchAt(['A', 'B'], 1, 3, 2), { rowLabel: 'A', columnNumber: 3 });
  assert.deepEqual(seatBatchAt(['A', 'B'], 1, 3, 3), { rowLabel: 'B', columnNumber: 1 });
  assert.deepEqual(seatBatchAt(['A', 'B'], 1, 3, 5), { rowLabel: 'B', columnNumber: 3 });
  assert.equal(seatBatchCount(['A', 'B'], 1, 3), 6);
});

test('lý do chặn nói rõ từng trường hợp, và entries luôn rỗng khi bị chặn', () => {
  const cases = [
    [{ ...base, zoneId: '' }, /Khu vật lý/],
    [{ ...base, prefix: '  ' }, /tiền tố/],
    [{ ...base, rows: '' }, /Nhập hàng/],
    [{ ...base, rows: 'D-A' }, /phải ở sau/],
    [{ ...base, start: '' }, /Số ghế phải là số nguyên/],
    [{ ...base, start: '0' }, /Số ghế phải là số nguyên/],
    [{ ...base, start: '1.5' }, /Số ghế phải là số nguyên/],
    [{ ...base, end: '0' }, /Đến số ghế/],
  ];

  for (const [input, pattern] of cases) {
    const plan = seatBatchPlan(input);
    assert.match(plan.blocked, pattern, JSON.stringify(input));
    assert.deepEqual(plan.entries, []);
    assert.equal(plan.total, 0);
    assert.equal(plan.preview, null);
  }
});

test('vượt 3.600 ghế thì chặn và nói rõ số đang chọn', () => {
  const plan = seatBatchPlan({ ...base, rows: 'A-Z', start: '1', end: '200' });

  assert.match(plan.blocked, /26 hàng × 200 số = 5200 ghế/);
  assert.match(plan.blocked, new RegExp(`tối đa ${SEAT_BATCH_MAX} ghế`));
});

test('đúng 3.600 thì KHÔNG chặn (cận biên)', () => {
  // 18 hàng × 200 số = 3600
  const plan = seatBatchPlan({ ...base, rows: 'A-R', start: '1', end: '200' });

  assert.equal(plan.blocked, null);
  assert.equal(plan.total, SEAT_BATCH_MAX);
});

test('mã sinh ra vượt 64 ký tự thì chặn ngay, kèm mã dài nhất', () => {
  // Mã là SINH RA nên không chặn được bằng maxLength của ô nhập; nếu để lọt thì
  // người dùng nhận 400 "Mã ghế tối đa 64 ký tự" mà không biết ghế nào trong lô.
  const longPrefix = 'X'.repeat(SEAT_CODE_MAX);
  const plan = seatBatchPlan({ ...base, prefix: longPrefix, rows: 'A-H', end: '8' });

  assert.match(plan.blocked, /Mã ghế dài nhất/);
  assert.match(plan.blocked, /vượt mức 64 ký tự/);
  assert.deepEqual(plan.entries, []);

  // Cận biên: 61 ký tự tiền tố + '-' + 'A' + '1' = ĐÚNG 64 ký tự -> hợp lệ.
  const atMax = seatBatchPlan({ ...base, prefix: 'X'.repeat(61), rows: 'A' });
  assert.equal(atMax.blocked, null);
  assert.equal(atMax.entries[0].seatCode.length, SEAT_CODE_MAX);

  // Thêm một ký tự là 65 -> vượt, phải chặn.
  const overLimit = seatBatchPlan({ ...base, prefix: 'X'.repeat(62), rows: 'A' });
  assert.match(overLimit.blocked, /vượt mức 64 ký tự/);
});

