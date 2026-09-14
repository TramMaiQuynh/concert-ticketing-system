import { useEffect, useRef, useCallback, useState, useId, isValidElement, cloneElement } from 'react';
import { createPortal } from 'react-dom';
import { IconCheck, IconAlert, IconInfo, IconX, IconInbox } from './icons';

/**
 * Primitive giao diện.
 *
 * Mọi trang chỉ được dựng từ những thành phần ở đây, không viết `style={{}}` rời
 * rạc nữa. Lợi ích không phải là ít gõ hơn mà là: một thay đổi ở đây áp cho toàn
 * hệ thống, và không có chuyện hai màn hình cùng loại lại lệch nhau vài pixel.
 */

/* ══ NÚT ═══════════════════════════════════════════════════════════════════ */

/**
 * @param {'primary'|'secondary'|'ghost'|'danger'|'danger-quiet'} variant
 * @param {'sm'|'md'|'lg'} size
 * @param {boolean} loading  khoá nút và hiện vòng xoay, GIỮ NGUYÊN bề rộng
 */
export function Button({
  variant = 'secondary', size = 'md', loading = false, block = false,
  icon, iconEnd, children, className = '', disabled, ...rest
}) {
  return (
    <button
      type="button"
      className={[
        'btn', `btn--${variant}`,
        size !== 'md' && `btn--${size}`,
        block && 'btn--block',
        !children && 'btn--icon',
        className,
      ].filter(Boolean).join(' ')}
      data-loading={loading || undefined}
      disabled={disabled || loading}
      {...rest}
    >
      {icon}
      {children}
      {iconEnd}
    </button>
  );
}

/* ══ TRƯỜNG NHẬP ═══════════════════════════════════════════════════════════ */

/**
 * Nhãn — ô nhập — gợi ý — lỗi, nối với nhau đúng chuẩn tiếp cận.
 *
 * `htmlFor`/`id` và `aria-describedby` được nối tự động: trình đọc màn hình đọc
 * được nhãn khi vào ô, và đọc cả gợi ý lẫn thông báo lỗi. Nếu để mỗi trang tự
 * nối tay thì gần như chắc chắn sẽ có chỗ quên.
 */
/**
 * Phần tử con này có nhận được thuộc tính id để nhãn trỏ tới không?
 *
 * Thẻ form thật thì đương nhiên nhận. Input/Select/Textarea của chính bộ primitive
 * này chỉ là vỏ mỏng trải `...rest` xuống thẻ thật nên cũng nhận. Mọi thứ khác —
 * một <div> bọc, một thành phần lạ — thì không, và ta không gắn bừa: id đặt lên
 * <div> không biến nó thành ô nhập, chỉ làm nhãn trỏ tới thứ không hợp lệ.
 */
function acceptsFieldId(el) {
  if (typeof el.type === 'string') {
    return el.type === 'input' || el.type === 'select' || el.type === 'textarea';
  }
  return el.type === Input || el.type === Select || el.type === Textarea;
}

export function Field({ label, hint, error, required, children, id }) {
  // useId là API React dành riêng cho việc này: sinh id ổn định qua các lần render
  // và duy nhất trên toàn cây. Bản trước dùng một biến đếm module cộng useRef rồi
  // đọc `.current` ngay trong thân render — vừa sai nguyên tắc (ref không được đọc
  // lúc render), vừa sinh id khác nhau giữa server và client nếu sau này dựng SSR.
  const gen = useId();
  const auto = id ?? gen;
  const hintId = hint ? `${auto}-hint` : undefined;
  const errId = error ? `${auto}-err` : undefined;
  const describedBy = [hintId, errId].filter(Boolean).join(' ') || undefined;

  // Nối nhãn với ô nhập. Trước đây htmlFor luôn trỏ tới `auto`, nhưng id chỉ được
  // truyền xuống khi children là HÀM — mà hầu hết trang lại viết <input> trực tiếp.
  // Kết quả là 107 nhãn trỏ vào hư không: bấm nhãn không đưa được con trỏ vào ô,
  // và trình đọc màn hình đọc ô đó là không tên. Ở đây ta tự gắn id vào phần tử
  // con khi nó nhận được, và KHÔNG đặt htmlFor khi không gắn được — thà không có
  // liên kết còn hơn có một liên kết gãy.
  const single = typeof children === 'function' || Array.isArray(children) ? null : children;
  const bindable = isValidElement(single) && acceptsFieldId(single) && single.props.id == null;
  const control = bindable
    ? cloneElement(single, {
        id: auto,
        'aria-describedby': single.props['aria-describedby'] ?? describedBy,
        'aria-invalid': single.props['aria-invalid'] ?? (error ? true : undefined),
      })
    : children;
  const forId = bindable ? auto
    : isValidElement(single) && single.props.id ? single.props.id
    : typeof children === 'function' ? auto
    : undefined;

  return (
    <div className="field">
      {label && (
        <label className="field__label" htmlFor={forId}>
          {label}{required && <span className="field__req" aria-hidden> *</span>}
        </label>
      )}
      {typeof children === 'function'
        ? children({ id: auto, 'aria-describedby': describedBy, 'aria-invalid': error ? true : undefined })
        : control}
      {hint && <span className="field__hint" id={hintId}>{hint}</span>}
      {error && <span className="field__error" id={errId} role="alert">{error}</span>}
    </div>
  );
}

export function Input({ className = '', ...rest }) {
  return <input className={`input ${className}`} {...rest} />;
}

export function Textarea({ className = '', ...rest }) {
  return <textarea className={`textarea ${className}`} {...rest} />;
}

/**
 * Ô chọn từ một miền giá trị của database.
 * `options` là mảng chuỗi thô; `labels` ánh xạ sang tiếng Việt để hiển thị —
 * giá trị gửi lên máy chủ luôn là chuỗi thô, không bao giờ là nhãn.
 */
export function Select({
  value, onChange, options, labels, allowEmpty, emptyLabel = '— giữ nguyên —',
  className = '', ...rest
}) {
  return (
    <select
      className={`select ${className}`}
      value={value ?? ''}
      onChange={(e) => onChange(e.target.value)}
      {...rest}
    >
      {allowEmpty && <option value="">{emptyLabel}</option>}
      {options.map((o) => <option key={o} value={o}>{labels?.[o] ?? o}</option>)}
    </select>
  );
}

export function Checkbox({ label, checked, onChange, hint, disabled }) {
  return (
    <div className="field checkbox-field">
      <label className="checkbox-field__label">
        <input
          type="checkbox" className="checkbox"
          checked={!!checked} disabled={disabled}
          onChange={(e) => onChange(e.target.checked)}
        />
        <span>{label}</span>
      </label>
      {hint && <span className="field__hint">{hint}</span>}
    </div>
  );
}

/* ══ BỀ MẶT ════════════════════════════════════════════════════════════════ */

export function Card({ children, className = '', ...rest }) {
  return <div className={`card ${className}`} {...rest}>{children}</div>;
}

/** Khối chức năng có tiêu đề và phần giải thích nghiệp vụ. */
const PANEL_CONTEXT = {
  create: 'Tạo mới',
  edit: 'Cập nhật',
  workflow: 'Vận hành',
  inventory: 'Kho vé',
  attention: 'Cần xác nhận',
};

export function Panel({ title, subtitle, aside, children, footer, tone = 'default' }) {
  const context = PANEL_CONTEXT[tone];
  return (
    <section className={`card card--panel card--panel--${tone}`}>
      {(title || aside) && (
        <header className="card__header panel__header">
          <div className="grow">
            {context && <div className="panel__context">{context}</div>}
            {title && <h3>{title}</h3>}
            {subtitle && <p className="panel__subtitle">{subtitle}</p>}
          </div>
          {aside}
        </header>
      )}
      <div className="card__body">{children}</div>
      {footer && <div className="card__footer">{footer}</div>}
    </section>
  );
}

export function PageHeader({ title, subtitle, actions, back }) {
  return (
    <div className="page-header">
      <div className="grow">
        {back}
        <h1>{title}</h1>
        {subtitle && <p className="page-header__sub">{subtitle}</p>}
      </div>
      {actions && <div className="row wrap gap-2">{actions}</div>}
    </div>
  );
}

/* ══ TÍN HIỆU TRẠNG THÁI ═══════════════════════════════════════════════════ */

/**
 * Badge trạng thái.
 *
 * Luôn có CẢ chấm màu lẫn chữ. Chỉ dùng màu để phân biệt trạng thái là không
 * đọc được với người mù màu đỏ-lục (khoảng 1/12 nam giới) — chữ mới là thứ
 * mang thông tin, màu chỉ là hỗ trợ quét nhanh.
 */
export function Badge({ tone = 'neutral', size, children, ...rest }) {
  return (
    <span className={`badge badge--${tone}${size === 'lg' ? ' badge--lg' : ''}`} {...rest}>
      <span className="badge__dot" aria-hidden />
      {children}
    </span>
  );
}

const ALERT_ICON = {
  info: <IconInfo size={15} />,
  success: <IconCheck size={15} />,
  warning: <IconAlert size={15} />,
  danger: <IconAlert size={15} />,
};

export function Alert({ tone = 'info', children, ...rest }) {
  return (
    <div className={`alert alert--${tone}`} role={tone === 'danger' ? 'alert' : 'status'} {...rest}>
      <span className="alert__icon">{ALERT_ICON[tone]}</span>
      <div className="grow">{children}</div>
    </div>
  );
}

/** Băng kết quả của một thao tác — dùng chung cho mọi form. */
export function ResultBanner({ state }) {
  if (!state?.text) return null;
  return (
    <div style={{ marginTop: 'var(--space-4)' }}>
      <Alert tone={state.type === 'success' ? 'success' : 'danger'}>{state.text}</Alert>
    </div>
  );
}

export function Pill({ as = 'span', children, ...rest }) {
  const Tag = as;
  return <Tag className="pill" {...rest}>{children}</Tag>;
}

/* ══ TRẠNG THÁI CHỜ VÀ RỖNG ════════════════════════════════════════════════ */

export function Skeleton({ w = '100%', h = 16, r, style }) {
  return (
    <div
      className="skeleton"
      style={{ width: w, height: h, borderRadius: r ?? 'var(--radius-sm)', ...style }}
      aria-hidden
    />
  );
}

export function EmptyState({ icon, title, children, action }) {
  return (
    <div className="empty">
      <div className="empty__icon">{icon ?? <IconInbox size={20} />}</div>
      <h4>{title}</h4>
      {children && <p className="text-sm text-secondary" style={{ maxWidth: '46ch' }}>{children}</p>}
      {action && <div style={{ marginTop: 'var(--space-2)' }}>{action}</div>}
    </div>
  );
}

/* ══ HỘP THOẠI ═════════════════════════════════════════════════════════════ */

/**
 * Hộp thoại chặn.
 *
 * Ba việc mà một hộp thoại tự làm phải có, và rất hay bị bỏ sót:
 *   1. Đóng bằng phím Esc.
 *   2. Khoá cuộn trang nền — nếu không, cuộn chuột sẽ trượt trang phía sau.
 *   3. Đưa focus vào trong khi mở và TRẢ focus về đúng phần tử cũ khi đóng.
 *      Thiếu bước này, người dùng bàn phím bị ném về đầu trang.
 */
export function Modal({ open, onClose, title, children, footer, labelledBy }) {
  const panelRef = useRef(null);
  const restoreRef = useRef(null);

  useEffect(() => {
    if (!open) return undefined;

    restoreRef.current = document.activeElement;
    const prevOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';

    const onKey = (e) => { if (e.key === 'Escape') onClose?.(); };
    document.addEventListener('keydown', onKey);

    // Đưa focus vào hộp thoại ở khung hình kế tiếp, sau khi đã gắn vào DOM.
    const t = requestAnimationFrame(() => panelRef.current?.focus());

    return () => {
      document.removeEventListener('keydown', onKey);
      document.body.style.overflow = prevOverflow;
      cancelAnimationFrame(t);
      restoreRef.current?.focus?.();
    };
  }, [open, onClose]);

  if (!open) return null;

  return createPortal(
    <div
      className="overlay"
      onMouseDown={(e) => { if (e.target === e.currentTarget) onClose?.(); }}
    >
      <div
        className="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby={labelledBy ?? 'modal-title'}
        tabIndex={-1}
        ref={panelRef}
      >
        {title && (
          <header className="card__header row gap-3" style={{ justifyContent: 'space-between' }}>
            <h3 id="modal-title" className="grow">{title}</h3>
            <Button variant="ghost" size="sm" onClick={onClose} aria-label="Đóng">
              <IconX size={15} />
            </Button>
          </header>
        )}
        <div className="card__body">{children}</div>
        {footer && <div className="card__footer row wrap gap-2" style={{ justifyContent: 'flex-end' }}>{footer}</div>}
      </div>
    </div>,
    document.body,
  );
}

/**
 * Hộp xác nhận cho hành động không hoàn tác được.
 *
 * `danger` đổi nút chính sang đỏ. Dùng cho hủy vé, hủy concert, khoá tài khoản —
 * những việc mà bấm nhầm là mất dữ liệu hoặc mất tiền thật.
 */
export function ConfirmDialog({
  open, onClose, onConfirm, title, children,
  confirmText = 'Xác nhận', cancelText = 'Quay lại', danger, loading,
}) {
  return (
    <Modal
      open={open}
      onClose={loading ? undefined : onClose}
      title={title}
      footer={
        <>
          <Button onClick={onClose} disabled={loading}>{cancelText}</Button>
          <Button variant={danger ? 'danger' : 'primary'} onClick={onConfirm} loading={loading}>
            {confirmText}
          </Button>
        </>
      }
    >
      <div className="text-sm text-secondary" style={{ lineHeight: 'var(--leading-sm)' }}>
        {children}
      </div>
    </Modal>
  );
}

/* ══ TAB ═══════════════════════════════════════════════════════════════════ */

export function Tabs({ value, onChange, items }) {
  return (
    <div className="tabs" role="tablist">
      {items.map((it) => (
        <button
          key={it.value}
          type="button"
          role="tab"
          className="tab"
          aria-selected={value === it.value}
          onClick={() => onChange(it.value)}
        >
          {it.label}
        </button>
      ))}
    </div>
  );
}

/* ══ HOOK THAO TÁC ═════════════════════════════════════════════════════════ */

/**
 * Bọc một lời gọi API: tự khoá nút khi đang gửi, tự dịch lỗi, tự báo kết quả.
 *
 * Việc khoá nút không phải chi tiết thẩm mỹ. Nhiều endpoint ở đây KHÔNG idempotent
 * (tạo địa điểm, tạo ghế, tạo khuyến mãi). Bấm hai lần vì tưởng chưa ăn sẽ tạo ra
 * hai bản ghi trùng mà API không có đường xoá.
 *
 * `apiError` được truyền vào thay vì import trực tiếp, để file primitive này không
 * phụ thuộc vào tầng gọi mạng.
 */
export function useAction(translateError) {
  const [busy, setBusy] = useState(false);
  const [state, setState] = useState({ text: '', type: '' });

  const run = useCallback(async (fn, successText) => {
    setBusy(true);
    setState({ text: '', type: '' });
    try {
      const result = await fn();
      const text = typeof successText === 'function' ? successText(result) : successText;
      if (text) setState({ text, type: 'success' });
      return result;
    } catch (err) {
      setState({ text: translateError ? translateError(err) : 'Đã có lỗi xảy ra.', type: 'error' });
      return undefined;
    } finally {
      setBusy(false);
    }
  }, [translateError]);

  const reset = useCallback(() => setState({ text: '', type: '' }), []);

  return { busy, state, setState, reset, run };
}
