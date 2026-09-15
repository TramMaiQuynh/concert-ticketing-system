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

export function Check({ label, checked, onChange, hint, disabled = false }) {
  return <Checkbox label={label} checked={checked} onChange={onChange} hint={hint} disabled={disabled} />;
}

/**
 * Lưu ý `aside`: bản trước quên chuyển tiếp prop này, nên mọi hành động đặt ở
 * góc phải tiêu đề khối — nút "dùng bố cục mẫu", ô chọn bản ghi để sửa — biến
 * mất mà không có lỗi nào. Đây đúng là kiểu hỏng im lặng của một lớp chuyển
 * tiếp: React bỏ qua prop không dùng, build vẫn xanh, và chỉ lộ ra khi có người
 * đi tìm cái nút không tồn tại.
 */
export function Panel({ title, subtitle, aside, children, footer, tone }) {
  return (
    <UiPanel title={title} subtitle={subtitle} aside={aside} footer={footer} tone={tone}>
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

/** Chọn bản ghi từ danh mục máy chủ hoặc nhập ID đã biết. */
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
              value={items.some((it) => String(it.id) === String(value)) ? String(value) : ''}
              onChange={(v) => v && onChange(v)}
              options={items.map((it) => String(it.id))}
              labels={Object.fromEntries(items.map((it) => [String(it.id), `#${it.id} · ${it.name}`]))}
              allowEmpty
              emptyLabel={'Chọn từ danh sách (' + items.length + ')'}
              aria-label={label + ': chọn từ danh sách'}
              className="grow"
            />
          )}
        </div>
      )}
    </UiField>
  );
}

/** Chọn nhiều bản ghi trong một yêu cầu, giữ thứ tự hiển thị đã chọn. */
export function MultiIdPicker({ label, hint, items, values = [], onChange, disabled = false }) {
  const selected = [...new Set(values.map(String))];
  const remaining = items.filter((item) => !selected.includes(String(item.id)));
  const labels = Object.fromEntries(items.map((item) => [String(item.id), '#' + item.id + ' · ' + item.name]));

  const remove = (id) => onChange(selected.filter((value) => value !== String(id)));
  const move = (index, direction) => {
    const next = [...selected];
    const target = index + direction;
    if (target < 0 || target >= next.length) return;
    [next[index], next[target]] = [next[target], next[index]];
    onChange(next);
  };

  return (
    <UiField label={label} hint={hint} required>
      <div className="stack gap-2">
        <UiSelect
          value=""
          onChange={(id) => id && onChange([...selected, id])}
          options={remaining.map((item) => String(item.id))}
          labels={labels}
          allowEmpty
          emptyLabel={'Chọn từ danh sách (' + items.length + ')'}
          aria-label={label + ': chọn từ danh sách'}
          disabled={disabled}
        />
        {selected.length > 0 ? (
          <ol className="multi-picker__selected" aria-label={label + ' đã chọn'}>
            {selected.map((id, index) => (
              <li key={id} className="multi-picker__item">
                <span className="multi-picker__name">{labels[id] ?? '#' + id}</span>
                <span className="row gap-1">
                  <button type="button" className="btn btn--secondary btn--sm multi-picker__move" onClick={() => move(index, -1)}
                          disabled={disabled || index === 0} aria-label={'Đưa ' + (labels[id] ?? '#' + id) + ' lên trước'}>↑</button>
                  <button type="button" className="btn btn--secondary btn--sm multi-picker__move" onClick={() => move(index, 1)}
                          disabled={disabled || index === selected.length - 1} aria-label={'Đưa ' + (labels[id] ?? '#' + id) + ' xuống sau'}>↓</button>
                  <button type="button" className="btn btn--danger-quiet btn--sm multi-picker__remove" onClick={() => remove(id)}
                          disabled={disabled}
                          aria-label={'Bỏ ' + (labels[id] ?? '#' + id)}>Bỏ</button>
                </span>
              </li>
            ))}
          </ol>
        ) : (
          <span className="field__hint">Chưa chọn bản ghi nào.</span>
        )}
      </div>
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
