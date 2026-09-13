import { useState } from 'react';
import api from '../../api/client';
import { Field, Select, Panel, Banner, useAction } from '../../components/form';
import { formatDateTime } from '../../lib/format';

/**
 * Tra cứu nhật ký kiểm toán (FR59/FR59a) — chỉ Admin.
 *
 * Hai lớp bảo vệ độc lập, không lớp nào đủ một mình:
 *   - Endpoint mang [Authorize(Roles = "Admin")].
 *   - VW_AuditTrail tự trả 0 dòng cho phiên không giữ Role Admin (RLS qua
 *     SESSION_CONTEXT), nên kể cả khi thuộc tính trên bị gỡ nhầm thì dữ liệu
 *     vẫn không rò ra. Bảng AuditRecord gốc vẫn bị DENY với mọi kết nối.
 *
 * Câu hỏi chính của FR59a là "lịch sử thay đổi của MỘT đối tượng", nên form đặt
 * cặp Loại đối tượng + ID lên đầu; khoảng thời gian là bộ lọc phụ (FR56).
 */

// Đúng các giá trị EntityType mà stored procedure ghi vào AuditRecord.
const ENTITY_TYPES = [
  'Booking', 'Payment', 'Refund', 'Ticket', 'Concert', 'EventSeat',
  'WaitlistEntry', 'QueueEntry', 'UserRoleAssignment', 'CheckinStaffAssignment',
];

const ENTITY_TYPE_LABEL = {
  Booking: 'Đơn đặt vé (Booking)',
  Payment: 'Giao dịch thanh toán (Payment)',
  Refund: 'Khoản hoàn tiền (Refund)',
  Ticket: 'Vé (Ticket)',
  Concert: 'Sự kiện (Concert)',
  EventSeat: 'Ghế trong kho vé (EventSeat)',
  WaitlistEntry: 'Đăng ký danh sách chờ',
  QueueEntry: 'Lượt xếp hàng đợi',
  UserRoleAssignment: 'Phân quyền người dùng',
  CheckinStaffAssignment: 'Phân công soát vé',
};

export default function Audit() {
  const act = useAction();
  const [entityType, setEntityType] = useState('');
  const [entityId, setEntityId] = useState('');
  const [from, setFrom] = useState('');
  const [to, setTo] = useState('');
  const [rows, setRows] = useState(null);

  const search = (e) => {
    e.preventDefault();
    setRows(null);
    act.run(async () => {
      const params = {};
      if (entityType) params.entityType = entityType;
      if (entityId.trim()) params.entityId = entityId.trim();
      if (from) params.from = from;
      if (to) params.to = to;
      const res = await api.get('/admin/audit', { params });
      setRows(res.data);
    });
  };

  return (
    <>
      <Panel
        title="Tra cứu nhật ký kiểm toán"
        subtitle="Mọi thay đổi nghiệp vụ đều để lại dấu vết không sửa được. Bỏ trống tất cả để xem các sự kiện gần nhất; điền Loại đối tượng và ID để lấy toàn bộ lịch sử của riêng đối tượng đó."
      >
        <form onSubmit={search}>
          <div className="field-grid">
            <Field label="Loại đối tượng" hint="Bỏ trống để tra cứu mọi loại.">
              <Select
                value={entityType} onChange={setEntityType}
                options={['', ...ENTITY_TYPES]}
                labels={{ '': '— Tất cả —', ...ENTITY_TYPE_LABEL }}
              />
            </Field>
            <Field label="ID đối tượng" hint="Ví dụ: số hiệu Booking. Bỏ trống để không lọc.">
              <input value={entityId} onChange={(e) => setEntityId(e.target.value)} maxLength={64} />
            </Field>
          </div>

          <div className="field-grid" style={{ marginTop: '16px' }}>
            <Field label="Từ thời điểm">
              <input type="datetime-local" value={from} onChange={(e) => setFrom(e.target.value)} />
            </Field>
            <Field label="Đến thời điểm" hint="Không bao gồm mốc này (nửa mở).">
              <input type="datetime-local" value={to} onChange={(e) => setTo(e.target.value)} />
            </Field>
          </div>

          <button className="btn-primary" style={{ marginTop: '16px' }} disabled={act.busy}>
            {act.busy ? 'Đang tra cứu…' : 'Tra cứu'}
          </button>
          <Banner state={act.state} />
        </form>
      </Panel>

      {rows && (
        <Panel title={`Kết quả (${rows.length})`}>
          {rows.length === 0 ? (
            <div className="field-hint">
              Không có bản ghi nào khớp điều kiện tra cứu.
            </div>
          ) : (
            <>
              <div className="field-hint" style={{ marginBottom: '12px' }}>
                Máy chủ giới hạn tối đa 500 bản ghi mỗi lần tra cứu — hãy thu hẹp
                khoảng thời gian nếu cần xem xa hơn.
              </div>
              <div className="table-wrap">
                <table className="data">
                  <thead>
                    <tr>
                      <th>Thời điểm</th><th>Sự kiện</th><th>Đối tượng</th>
                      <th>Thao tác</th><th>Người thực hiện</th><th>Giá trị mới</th>
                    </tr>
                  </thead>
                  <tbody>
                    {rows.map((r) => (
                      <tr key={r.auditID}>
                        <td>{formatDateTime(r.eventTimestamp)}</td>
                        <td>{r.eventType}</td>
                        <td>
                          {ENTITY_TYPE_LABEL[r.entityType] ?? r.entityType}
                          <span className="text-muted"> #{r.entityID}</span>
                        </td>
                        <td>{r.action}</td>
                        <td>{r.actorUsername}</td>
                        <td style={{ maxWidth: 320, wordBreak: 'break-all' }}>
                          <span className="text-muted">{r.newValue ?? '—'}</span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </Panel>
      )}
    </>
  );
}
