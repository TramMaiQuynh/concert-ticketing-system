import { useState } from 'react';
import api from '../../api/client';
import { useAdminCatalog } from '../../lib/adminCatalog';
import { useConcertOptions } from '../../lib/concertOptions';
import { Field, Select, Check, Panel, Banner, IdPicker, IdPill, useAction } from '../../components/form';
import { toApiDateTime } from '../../lib/format';
import {
  DiscountType, DISCOUNT_TYPE_LABEL, PromotionStatus, DiscountCodeStatus, ADMIN_STATUS_LABEL,
} from '../../domain/enums';

/**
 * Khuyến mãi và mã giảm giá.
 *
 * Quan hệ cần nắm: Promotion là chính sách giảm giá gắn với một concert. DiscountCode
 * là chuỗi ký tự khách gõ, thuộc về một Promotion. Một Promotion có thể yêu cầu mã
 * (CodeRequiredFlag) hoặc tự động áp mà không cần mã.
 *
 * Trạng thái Promotion KHÔNG có giá trị 'Expired': hết hạn là suy ra từ khoảng thời
 * gian hiệu lực chứ không lưu thành trạng thái riêng — lưu cả hai sẽ thành hai nguồn
 * sự thật lệch nhau (BR50d).
 */
export default function Promotions() {
  return (
    <>
      <CreatePromotion />
      <PromotionStatusSection />
      <CreateDiscountCode />
      <DiscountCodeStatusSection />
    </>
  );
}

/* ── Tạo khuyến mãi ──────────────────────────────────────────────────────── */

function CreatePromotion() {
  const { options: concerts } = useConcertOptions();
  const { items } = useAdminCatalog('promotion');
  const act = useAction();

  const [concertId, setConcertId] = useState('');
  const [f, setF] = useState({
    promotionName: '', promotionDescription: '',
    discountType: DiscountType.FixedAmount, discountValue: '',
    startDatetime: '', endDatetime: '',
    usageLimit: '', codeRequiredFlag: true,
    maxApplicableQuantity: '', maxDiscountAmount: '',
  });
  const set = (k) => (v) => setF((s) => ({ ...s, [k]: v }));
  const num = (v) => (String(v).trim() === '' ? null : Number(v));

  const isPercent = f.discountType === DiscountType.Percentage;

  return (
    <Panel
      title="Tạo khuyến mãi"
      tone="create"
      subtitle="Khuyến mãi gắn với một concert cụ thể. Giá trị giảm được áp khi khách bấm áp mã ở trang thanh toán, và bị KHOÁ lại khi khách đã khởi tạo giao dịch."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            const res = await api.post(`/admin/concerts/${Number(concertId)}/promotions`, {
              promotionName: f.promotionName.trim(),
              promotionDescription: f.promotionDescription.trim() || null,
              discountType: f.discountType,
              discountValue: Number(f.discountValue),
              startDatetime: toApiDateTime(f.startDatetime),
              endDatetime: toApiDateTime(f.endDatetime),
              usageLimit: num(f.usageLimit),
              codeRequiredFlag: f.codeRequiredFlag,
              maxApplicableQuantity: num(f.maxApplicableQuantity),
              maxDiscountAmount: num(f.maxDiscountAmount),
            });
            return res.data.id;
          }, (id) => `Đã tạo khuyến mãi. ID = ${id}. Khuyến mãi sinh ra ở trạng thái Draft — `
                   + `phải chuyển sang Active ở khối dưới thì mới áp được.`);
        }}
      >
        <IdPicker label="Concert áp dụng" items={concerts} value={concertId} onChange={setConcertId} />

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Tên khuyến mãi" required>
            <input value={f.promotionName} onChange={(e) => set('promotionName')(e.target.value)} maxLength={255} required />
          </Field>
          <Field label="Kiểu giảm giá" required>
            <Select value={f.discountType} onChange={set('discountType')}
                    options={Object.values(DiscountType)} labels={DISCOUNT_TYPE_LABEL} />
          </Field>
          <Field
            label={isPercent ? 'Phần trăm giảm (%)' : 'Số tiền giảm (₫)'}
            hint={isPercent ? 'Ví dụ 15 nghĩa là giảm 15%.' : 'Số nguyên đồng, ví dụ 200000.'}
            required
          >
            <input
              type="number" min="1" step="1"
              max={isPercent ? 100 : undefined}
              value={f.discountValue} onChange={(e) => set('discountValue')(e.target.value)} required
            />
          </Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Hiệu lực từ" required>
            <input type="datetime-local" value={f.startDatetime} onChange={(e) => set('startDatetime')(e.target.value)} required />
          </Field>
          <Field label="Hiệu lực đến" required>
            <input type="datetime-local" value={f.endDatetime} onChange={(e) => set('endDatetime')(e.target.value)} required />
          </Field>
          <Field label="Tổng lượt dùng tối đa" hint="Bỏ trống nghĩa là không giới hạn.">
            <input type="number" min="1" value={f.usageLimit} onChange={(e) => set('usageLimit')(e.target.value)} />
          </Field>
        </div>

        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Số ghế tối đa được giảm / đơn" hint="Bỏ trống thì áp cho toàn bộ ghế trong đơn (BR36b).">
            <input type="number" min="1" value={f.maxApplicableQuantity} onChange={(e) => set('maxApplicableQuantity')(e.target.value)} />
          </Field>
          <Field label="Mức giảm tối đa / đơn (₫)" hint="Trần an toàn khi giảm theo phần trăm.">
            <input type="number" min="1" value={f.maxDiscountAmount} onChange={(e) => set('maxDiscountAmount')(e.target.value)} />
          </Field>
        </div>

        <div style={{ marginTop: '16px' }}>
          <Check
            label="Bắt buộc nhập mã giảm giá"
            checked={f.codeRequiredFlag} onChange={set('codeRequiredFlag')}
            hint="Bật thì khách phải gõ đúng một mã thuộc khuyến mãi này. Tắt thì khuyến mãi tự áp cho mọi đơn đủ điều kiện."
          />
        </div>

        <button
          className="btn-primary" style={{ marginTop: '20px' }}
          disabled={act.busy || !concertId || !f.promotionName.trim() || !f.discountValue || !f.startDatetime || !f.endDatetime}
        >
          {act.busy ? 'Đang tạo…' : 'Tạo khuyến mãi'}
        </button>
        <Banner state={act.state} />
      </form>

      {items.length > 0 && (
        <div style={{ marginTop: '20px', paddingTop: '16px', borderTop: '1px solid var(--border-subtle)', display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
          {items.slice(0, 20).map((it) => <IdPill key={it.id}>#{it.id} · {it.name}</IdPill>)}
        </div>
      )}
    </Panel>
  );
}

/* ── Trạng thái khuyến mãi ───────────────────────────────────────────────── */

function PromotionStatusSection() {
  const { items } = useAdminCatalog('promotion');
  const act = useAction();
  const [id, setId] = useState('');
  const [status, setStatus] = useState(PromotionStatus.Active);

  return (
    <Panel
      title="Trạng thái khuyến mãi"
      tone="workflow"
      subtitle="Draft là bản nháp chưa áp được. Active là đang chạy. Disabled là tắt hẳn. Không có trạng thái 'hết hạn' — hết hạn suy ra từ khoảng thời gian hiệu lực."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.put(`/admin/promotions/${Number(id)}/status`, { status }),
            `Đã chuyển khuyến mãi #${id} sang ${ADMIN_STATUS_LABEL[status]}.`,
          );
        }}
      >
        <div className="field-grid">
          <IdPicker label="Khuyến mãi" items={items} value={id} onChange={setId} />
          <Field label="Trạng thái mới" required>
            <Select value={status} onChange={setStatus}
                    options={Object.values(PromotionStatus)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>
        <button className="btn-primary" style={{ marginTop: '16px' }} disabled={act.busy || !id}>
          {act.busy ? 'Đang lưu…' : 'Đổi trạng thái'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Tạo mã giảm giá ─────────────────────────────────────────────────────── */

function CreateDiscountCode() {
  const promotions = useAdminCatalog('promotion');
  const { items } = useAdminCatalog('discountCode');
  const act = useAction();

  const [promotionId, setPromotionId] = useState('');
  const [code, setCode] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [globalLimit, setGlobalLimit] = useState('');
  const [perCustomer, setPerCustomer] = useState('');

  const num = (v) => (String(v).trim() === '' ? null : Number(v));

  return (
    <Panel
      title="Tạo mã giảm giá"
      tone="create"
      subtitle="Mã thuộc về một khuyến mãi. Giới hạn theo khách (BR36f) đếm số lần chính khách đó đã dùng mã, không phải tổng lượt dùng."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            const res = await api.post(`/admin/promotions/${Number(promotionId)}/discount-codes`, {
              codeValue: code.trim(),
              validFromDatetime: toApiDateTime(from),
              validToDatetime: toApiDateTime(to),
              globalUsageLimit: num(globalLimit),
              perCustomerUsageLimit: num(perCustomer),
            });
            setCode('');
            return res.data.id;
          }, (id) => `Đã tạo mã giảm giá. ID = ${id}.`);
        }}
      >
        <div className="field-grid">
          <IdPicker label="Thuộc khuyến mãi" items={promotions.items} value={promotionId} onChange={setPromotionId} />
          <Field label="Mã giảm giá" hint="Đây là chuỗi khách sẽ gõ ở trang thanh toán." required>
            <input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} maxLength={64} required />
          </Field>
        </div>
        <div className="field-grid" style={{ marginTop: '16px' }}>
          <Field label="Hiệu lực từ" hint="Bỏ trống thì theo thời hạn của khuyến mãi.">
            <input type="datetime-local" value={from} onChange={(e) => setFrom(e.target.value)} />
          </Field>
          <Field label="Hiệu lực đến">
            <input type="datetime-local" value={to} onChange={(e) => setTo(e.target.value)} />
          </Field>
          <Field label="Tổng lượt dùng tối đa">
            <input type="number" min="1" value={globalLimit} onChange={(e) => setGlobalLimit(e.target.value)} />
          </Field>
          <Field label="Lượt dùng tối đa / khách">
            <input type="number" min="1" value={perCustomer} onChange={(e) => setPerCustomer(e.target.value)} />
          </Field>
        </div>
        <button className="btn-primary" style={{ marginTop: '16px' }} disabled={act.busy || !promotionId || !code.trim()}>
          {act.busy ? 'Đang tạo…' : 'Tạo mã giảm giá'}
        </button>
        <Banner state={act.state} />
      </form>

      {items.length > 0 && (
        <div style={{ marginTop: '20px', paddingTop: '16px', borderTop: '1px solid var(--border-subtle)', display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
          {items.slice(0, 20).map((it) => <IdPill key={it.id}>#{it.id} · {it.name}</IdPill>)}
        </div>
      )}
    </Panel>
  );
}

/* ── Trạng thái mã giảm giá ──────────────────────────────────────────────── */

function DiscountCodeStatusSection() {
  const { items } = useAdminCatalog('discountCode');
  const act = useAction();
  const [id, setId] = useState('');
  const [status, setStatus] = useState(DiscountCodeStatus.Disabled);

  return (
    <Panel
      title="Trạng thái mã giảm giá"
      tone="workflow"
      subtitle="Tắt một mã bị lộ mà không phải tắt cả chương trình khuyến mãi."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.put(`/admin/discount-codes/${Number(id)}/status`, { status }),
            `Đã chuyển mã #${id} sang ${ADMIN_STATUS_LABEL[status]}.`,
          );
        }}
      >
        <div className="field-grid">
          <IdPicker label="Mã giảm giá" items={items} value={id} onChange={setId} />
          <Field label="Trạng thái mới" required>
            <Select value={status} onChange={setStatus}
                    options={Object.values(DiscountCodeStatus)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>
        <button className="btn-primary" style={{ marginTop: '16px' }} disabled={act.busy || !id}>
          {act.busy ? 'Đang lưu…' : 'Đổi trạng thái'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}
