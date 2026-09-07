import { apiError } from '../api/client';
import {
  Field as UiField, Select as UiSelect, Checkbox, Panel as UiPanel,
  ResultBanner, Input, Pill, useAction as useUiAction,
} from './ui';

/**
 * Lớp chuyển tiếp cho khu quản trị.
 *
 * Các trang quản trị đã được kiểm chứng chạy đúng với API thật (34/34 phép thử,
 * gửi đúng payload backend mong đợi). Viết lại chúng chỉ để đổi hình thức là rủi
 * ro không đáng: mỗi lần sửa là một cơ hội làm sai một tên trường mà build vẫn
 * xanh và lỗi chỉ lộ ra lúc chạy thật.
 *
 * Vì vậy file này giữ NGUYÊN giao diện lập trình cũ (Field, Select, Check, Panel,
 * Banner, IdPicker, IdPill, useAction) nhưng dựng chúng trên bộ primitive mới.
 * Kết quả: các trang quản trị nhận toàn bộ hệ thống thiết kế mới — token, dark
 * mode, vòng focus, trạng thái đang tải — mà không phải chạm vào một dòng logic
 * gọi API nào.
 */

export function Field({ label, hint, children, required }) {
  return <UiField label={label} hint={hint} required={required}>{children}</UiField>;
}

// XUẤT THẲNG, không bọc thêm một lớp. Bọc lại tạo ra một component KHÁC DANH TÍNH,
// nên Field không nhận ra đây là ô nhập và không gắn id — hệ quả là mọi <select>
// trong khu quản trị mất tên khả dụng. Lớp bọc này vốn không thêm gì cả.
export { UiSelect as Select };

export function Check({ label, checked, onChange, hint }) {
  return <Checkbox label={label} checked={checked} onChange={onChange} hint={hint} />;
}

/**
 * Lưu ý `aside`: bản trước quên chuyển tiếp prop này, nên mọi hành động đặt ở
 * góc phải tiêu đề khối — nút "dùng bố cục mẫu", ô chọn bản ghi để sửa — biến
 * mất mà không có lỗi nào. Đây đúng là kiểu hỏng im lặng của một lớp chuyển
 * tiếp: React bỏ qua prop không dùng, build vẫn xanh, và chỉ lộ ra khi có người
 * đi tìm cái nút không tồn tại.
 */
export function Panel({ title, subtitle, aside, children, footer }) {
  return (
    <UiPanel title={title} subtitle={subtitle} aside={aside} footer={footer}>
      {children}
    </UiPanel>
  );
}

export function Banner({ state }) {
  return <ResultBanner state={state} />;
}

export function IdPill({ children }) {
  return <Pill>{children}</Pill>;
}

/**
 * Ô chọn từ sổ tay cục bộ, LUÔN kèm đường nhập ID thủ công.
 *
 * Sổ tay chỉ là bộ nhớ tạm của trình duyệt (xem lib/localCatalog.js). Nếu chỉ cho
 * chọn từ sổ tay thì người dùng mở trên máy khác sẽ bị kẹt hoàn toàn — nên ô nhập
 * số luôn hiện diện và luôn là thứ được gửi đi.
 */
export function IdPicker({ label, hint, items, value, onChange, placeholder = 'Nhập ID…' }) {
  return (
    <UiField label={label} hint={hint} required>
      {(a) => (
        <div className="row gap-2">
          <Input
            {...a}
            type="number" min="1" inputMode="numeric"
            value={value}
            onChange={(e) => onChange(e.target.value)}
            placeholder={placeholder}
            style={{ flex: '0 0 132px' }}
          />
          {items.length > 0 && (
            <UiSelect
              value=""
              onChange={(v) => v && onChange(v)}
              options={items.map((it) => String(it.id))}
              labels={Object.fromEntries(items.map((it) => [String(it.id), `#${it.id} · ${it.name}`]))}
              allowEmpty
              emptyLabel={`— chọn từ sổ tay (${items.length}) —`}
              aria-label={`${label} — chọn từ sổ tay`}
              className="grow"
            />
          )}
        </div>
      )}
    </UiField>
  );
}

/**
 * Bọc một thao tác gọi API: tự khoá nút khi đang gửi, tự dịch lỗi, tự báo kết quả.
 *
 * Việc khoá nút không phải chi tiết thẩm mỹ: nhiều endpoint ở đây KHÔNG idempotent
 * (tạo Venue, tạo Seat, tạo Promotion). Bấm hai lần vì tưởng chưa ăn sẽ tạo ra hai
 * bản ghi trùng mà API không có đường xoá.
 */
export function useAction() {
  return useUiAction(apiError);
}
