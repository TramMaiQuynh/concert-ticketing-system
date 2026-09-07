import { createContext, useContext, useCallback, useState, useRef } from 'react';
import { createPortal } from 'react-dom';
import { IconCheck, IconAlert, IconInfo, IconX } from './icons';

/**
 * Thông báo nổi.
 *
 * Dùng cho kết quả của thao tác KHÔNG gắn với một form đang mở trên màn hình —
 * ví dụ hủy vé xong ở trang danh sách, hay lỗi giới hạn tần suất từ interceptor.
 * Kết quả của một form thì vẫn hiện ngay dưới form đó (ResultBanner), vì đặt xa
 * chỗ người dùng đang nhìn là cách chắc chắn để họ không đọc.
 *
 * Vùng chứa dùng `aria-live="polite"`: trình đọc màn hình đọc nội dung mới khi
 * người dùng ngơi tay, không cắt ngang giữa chừng.
 */

const ToastContext = createContext(null);

const ICON = {
  success: <IconCheck size={16} />,
  error: <IconAlert size={16} />,
  warning: <IconAlert size={16} />,
  info: <IconInfo size={16} />,
};

export function ToastProvider({ children }) {
  const [items, setItems] = useState([]);
  const seq = useRef(0);

  const dismiss = useCallback((id) => {
    setItems((list) => list.filter((t) => t.id !== id));
  }, []);

  const toast = useCallback((text, { type = 'info', duration = 5000 } = {}) => {
    const id = ++seq.current;
    setItems((list) => [...list, { id, text, type }]);
    if (duration > 0) setTimeout(() => dismiss(id), duration);
    return id;
  }, [dismiss]);

  return (
    <ToastContext.Provider value={toast}>
      {children}
      {createPortal(
        <div className="toast-region" aria-live="polite" aria-atomic="false">
          {items.map((t) => (
            <div key={t.id} className={`toast toast--${t.type}`}>
              <span style={{ flex: 'none', marginTop: '1px', color: `var(--${
                t.type === 'success' ? 'green' : t.type === 'error' ? 'red'
                : t.type === 'warning' ? 'amber' : 'blue'}-text)` }}
              >
                {ICON[t.type]}
              </span>
              <div className="grow">{t.text}</div>
              <button
                type="button"
                onClick={() => dismiss(t.id)}
                aria-label="Đóng thông báo"
                style={{
                  flex: 'none', background: 'none', border: 'none', cursor: 'pointer',
                  color: 'var(--text-muted)', padding: 2, marginTop: '1px',
                }}
              >
                <IconX size={14} />
              </button>
            </div>
          ))}
        </div>,
        document.body,
      )}
    </ToastContext.Provider>
  );
}

/** Trả về hàm `toast(text, { type })`. An toàn khi chưa có Provider (trả no-op). */
export function useToast() {
  return useContext(ToastContext) ?? (() => {});
}
