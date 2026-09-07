import { useState } from 'react';
import api from '../../api/client';
import { useCatalog } from '../../lib/localCatalog';
import { Field, Select, Panel, Banner, IdPicker, useAction } from '../../components/form';
import { RefundStatus } from '../../domain/enums';

/**
 * Hủy đơn và hoàn tiền — phía ban tổ chức.
 *
 * Quy trình có HAI bước tách rời, và đó là cố ý:
 *
 *   1. Tạo yêu cầu hoàn  → Refund ở trạng thái Pending. Booking đã hủy, ghế đã được
 *      trả lại kho, vé đã bị hủy. Nhưng TIỀN CHƯA đi đâu cả.
 *   2. Xác nhận đã hoàn  → Refund chuyển Confirmed, Payment chuyển Refunded.
 *      Bước này chỉ được bấm SAU KHI tiền thực sự đã về tài khoản khách ở cổng
 *      thanh toán. Bấm sớm là hệ thống ghi nhận đã hoàn trong khi khách chưa nhận
 *      được đồng nào.
 *
 * Và một yêu cầu hoàn tiền có BA kết cục, không phải hai (§10.1): ngoài Confirmed
 * còn Failed (cổng thanh toán từ chối) và Cancelled (yêu cầu bị hủy/từ chối trước
 * khi xử lý xong). Trước đây giao diện chỉ có đường đi tới Confirmed, nên một khoản
 * hoàn bị cổng từ chối không có cách nào đóng lại — nó nằm Pending vĩnh viễn và
 * không gì phân biệt được "đang chờ settle" với "đã thất bại". Khối Bước 3 là đường
 * đi còn thiếu đó.
 *
 * Số tiền hoàn KHÔNG nhập ở đây, và không có ô nào để nhập: sp_ProcessRefund tự tính
 * theo Concert.RefundPercentage (BR32a). Để người dùng gõ số tiền sẽ tạo ra một đường
 * vượt mặt chính sách hoàn tiền của chính concert đó.
 */
export default function Refunds() {
  return (
    <>
      <ProcessRefundSection />
      <ConfirmRefundSection />
      <CloseRefundSection />
    </>
  );
}

function ProcessRefundSection() {
  const { remember } = useCatalog('refund');
  const act = useAction();
  const [bookingId, setBookingId] = useState('');
  const [reason, setReason] = useState('');
  const [last, setLast] = useState(null);

  return (
    <Panel
      title="Bước 1 — Hủy đơn và tạo yêu cầu hoàn tiền"
      subtitle="Dùng khi ban tổ chức hủy đơn thay cho khách. Ghế được trả lại kho ngay, vé bị hủy ngay, còn khoản hoàn được tạo ở trạng thái chờ."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(async () => {
            const res = await api.post(`/bookings/${Number(bookingId)}/refund`, {
              reason: reason.trim() || null,
            });
            setLast(res.data);
            if (res.data?.refundId) {
              remember({ id: res.data.refundId, name: `từ booking #${bookingId}` });
            }
            return res.data;
          }, (d) => (d?.refundId
            ? `Đã hủy đơn và tạo yêu cầu hoàn tiền #${d.refundId}. Sang bước 2 sau khi tiền đã thực sự về tài khoản khách.`
            : d?.message ?? 'Đã hủy đơn.'));
        }}
      >
        <div className="field-grid">
          <Field label="BookingID" required>
            <input type="number" min="1" value={bookingId} onChange={(e) => setBookingId(e.target.value)} required />
          </Field>
          <Field label="Lý do hủy" hint="Không bắt buộc. Được ghi vào nhật ký kiểm toán.">
            <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} />
          </Field>
        </div>

        <div className="field-hint" style={{ marginTop: '12px' }}>
          Không có ô nhập số tiền — số tiền hoàn do database tự tính theo tỷ lệ hoàn của
          concert. Đơn chưa thanh toán hoặc concert đặt tỷ lệ hoàn bằng 0 sẽ hủy đơn mà
          không phát sinh khoản hoàn nào.
        </div>

        <button className="btn-danger" style={{ marginTop: '16px' }} disabled={act.busy || !bookingId}>
          {act.busy ? 'Đang xử lý…' : 'Hủy đơn và tạo yêu cầu hoàn'}
        </button>
        <Banner state={act.state} />
      </form>

      {last && last.refundId == null && (
        <div className="field-hint" style={{ marginTop: '12px' }}>
          Lần gọi này không tạo khoản hoàn nào — không cần làm bước 2.
        </div>
      )}
    </Panel>
  );
}

function ConfirmRefundSection() {
  const { items } = useCatalog('refund');
  const act = useAction();
  const [refundId, setRefundId] = useState('');

  return (
    <Panel
      title="Bước 2 — Xác nhận đã hoàn tiền xong"
      subtitle="Chỉ bấm sau khi cổng thanh toán đã chuyển tiền về cho khách. Thao tác này chuyển Refund sang Confirmed và Payment sang Refunded."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.post(`/refunds/${Number(refundId)}/confirm`),
            `Đã xác nhận hoàn tiền #${refundId}.`,
          );
        }}
      >
        <IdPicker label="RefundID" items={items} value={refundId} onChange={setRefundId} />

        <div className="field-hint" style={{ marginTop: '12px' }}>
          Gọi lại nhiều lần trên cùng một khoản hoàn đã xác nhận là an toàn: stored
          procedure xử lý idempotent để chịu được callback gửi lặp từ cổng thanh toán,
          và không cộng dồn số tiền.
        </div>

        <button className="btn-primary" style={{ marginTop: '16px' }} disabled={act.busy || !refundId}>
          {act.busy ? 'Đang xác nhận…' : 'Xác nhận đã hoàn tiền'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Bước 3: kết thúc yêu cầu mà KHÔNG chi trả ──────────────────────────── */

/**
 * Khác hẳn Bước 2, dù cùng nói về một khoản hoàn.
 *
 * Bước 2 khẳng định TIỀN ĐÃ VỀ với khách và kéo theo Payment chuyển trạng thái.
 * Bước 3 khẳng định điều ngược lại: yêu cầu này kết thúc mà khách KHÔNG nhận được
 * tiền — nên Payment giữ nguyên, không đồng nào rời tài khoản thu.
 *
 * Vì sao bắt buộc nhập lý do: đây là thao tác đóng một yêu cầu hoàn tiền của khách
 * hàng. Không có lý do thì sau này không ai truy được vì sao khoản đó bị bỏ.
 */
function CloseRefundSection() {
  const { items } = useCatalog('refund');
  const act = useAction();
  const [refundId, setRefundId] = useState('');
  const [status, setStatus] = useState(RefundStatus.Failed);
  const [reason, setReason] = useState('');

  return (
    <Panel
      title="Bước 3 — Kết thúc yêu cầu mà không hoàn tiền"
      subtitle="Dùng khi cổng thanh toán từ chối chuyển tiền, hoặc khi yêu cầu hoàn bị từ chối. Payment GIỮ NGUYÊN — không đồng nào rời tài khoản thu. Chỉ áp dụng cho khoản đang chờ xử lý."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.put(`/refunds/${Number(refundId)}/status`, { status, reason: reason.trim() }),
            status === RefundStatus.Failed
              ? `Đã ghi nhận khoản hoàn #${refundId} thất bại. Hạn mức hoàn của Payment được giải phóng.`
              : `Đã hủy yêu cầu hoàn tiền #${refundId}.`,
          );
        }}
      >
        <div className="field-grid">
          <IdPicker label="RefundID" items={items} value={refundId} onChange={setRefundId} />
          <Field label="Kết cục" required>
            <Select
              value={status} onChange={setStatus}
              options={[RefundStatus.Failed, RefundStatus.Cancelled]}
              labels={{
                Failed: 'Failed — cổng thanh toán từ chối',
                Cancelled: 'Cancelled — yêu cầu bị hủy / từ chối',
              }}
            />
          </Field>
        </div>

        <Field label="Lý do" hint="Bắt buộc. Được ghi vào nhật ký kiểm toán, không ghi đè lý do hoàn tiền gốc." required>
          <input value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} required />
        </Field>

        <div className="field-hint" style={{ marginTop: '12px' }}>
          Thao tác này giải phóng phần hạn mức mà khoản hoàn đang chiếm: database chỉ
          cộng dồn các khoản KHÔNG ở trạng thái Failed/Cancelled khi kiểm tổng hoàn
          tiền không vượt quá Payment. Khoản đã Confirmed thì không kết thúc kiểu này
          được — tiền đã đi rồi.
        </div>

        <button className="btn-danger" style={{ marginTop: '16px' }}
                disabled={act.busy || !refundId || !reason.trim()}>
          {act.busy ? 'Đang xử lý…' : 'Kết thúc yêu cầu'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}
