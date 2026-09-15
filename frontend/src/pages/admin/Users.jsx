import { useState } from 'react';
import api from '../../api/client';
import { useConcertOptions } from '../../lib/concertOptions';
import { Field, Select, Panel, Banner, useAction } from '../../components/form';
import {
  ASSIGNABLE_ROLES, RoleAction, UserStatus, AssignmentStatus, RoleStatus, ADMIN_STATUS_LABEL,
} from '../../domain/enums';

/**
 * Người dùng và phân quyền.
 *
 * Các thao tác ở đây đều là những việc không đảo ngược dễ dàng, nên giao diện nói
 * rõ hậu quả trước khi bấm thay vì để người dùng tự đoán.
 *
 * PHÂN QUYỀN TRONG TRANG: ba khối đầu (cấp/thu hồi vai trò, trạng thái vai trò,
 * khóa tài khoản) là việc CẤP DANH TÍNH ở phạm vi toàn hệ thống — chỉ Admin, đúng
 * như sp_AssignRole / sp_UpdateRoleStatus / sp_AdminUpdateUserStatus tự chặn ở tầng
 * database. Riêng khối phân công soát vé là việc VẬN HÀNH theo từng sự kiện, nên
 * Organizer cũng làm được cho concert thuộc sở hữu của mình (sp_AddCheckinStaffAssignment
 * kiểm tra Concert.OrganizerUserID). Cùng khuôn với Catalog: hiện cả trang cho hai
 * vai trò rồi ẩn đúng phần Admin-only, thay vì chặn cả trang.
 *
 * Lưu ý về ID người dùng: API không có endpoint tra cứu người dùng, nên phải nhập
 * UserID bằng số. Đây là giới hạn của backend chứ không phải lựa chọn thiết kế —
 * nói thẳng trên giao diện để người dùng biết phải lấy ID từ đâu.
 */
export default function Users({ isAdmin }) {
  return (
    <>
      {isAdmin && (
        <>
          <RoleSection />
          <RoleStatusSection />
          <UserStatusSection />
        </>
      )}
      <StaffAssignmentSection isAdmin={isAdmin} />
    </>
  );
}

/* ── Cấp / thu hồi vai trò ───────────────────────────────────────────────── */

function RoleSection() {
  const act = useAction();
  const [userId, setUserId] = useState('');
  const [roleName, setRoleName] = useState(ASSIGNABLE_ROLES[1]);
  const [action, setAction] = useState(RoleAction.Grant);

  const revokingAdmin = action === RoleAction.Revoke && roleName === 'Admin';

  return (
    <Panel
      title="Cấp và thu hồi vai trò"
      tone="workflow"
      subtitle="Một người có thể giữ nhiều vai trò cùng lúc. Database từ chối thu hồi vai trò Admin của Admin đang hoạt động CUỐI CÙNG — hệ thống không bao giờ được rơi vào trạng thái không còn quản trị viên nào (UAI01)."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.post('/admin/roles/assign', {
              targetUserId: Number(userId),
              roleName,
              grantOrRevoke: action,
            }),
            `Đã ${action === RoleAction.Grant ? 'cấp' : 'thu hồi'} vai trò ${roleName} cho người dùng #${userId}.`,
          );
        }}
      >
        <div className="field-grid">
          <Field label="UserID" hint="Số hiệu người dùng trong database." required>
            <input type="number" min="1" value={userId} onChange={(e) => setUserId(e.target.value)} required />
          </Field>
          <Field label="Vai trò" required>
            <Select value={roleName} onChange={setRoleName} options={ASSIGNABLE_ROLES} />
          </Field>
          <Field label="Hành động" required>
            <Select value={action} onChange={setAction}
                    options={Object.values(RoleAction)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>

        {revokingAdmin && (
          <div className="field-hint" style={{ color: 'var(--warning)', marginTop: '12px' }}>
            Đang thu hồi quyền Admin. Nếu đây là Admin hoạt động cuối cùng, database sẽ từ chối.
          </div>
        )}

        <button
          className={action === RoleAction.Revoke ? 'btn-danger' : 'btn-primary'}
          style={{ marginTop: '16px' }}
          disabled={act.busy || !userId}
        >
          {act.busy ? 'Đang xử lý…' : action === RoleAction.Grant ? 'Cấp vai trò' : 'Thu hồi vai trò'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Mở / đóng khả năng phân công của vai trò ────────────────────────────── */

/**
 * Khác hẳn khối bên trên, dù cùng nói về "vai trò".
 *
 * Khối trên thao tác trên MỘT NGƯỜI: cấp hoặc thu hồi vai trò của người đó.
 * Khối này thao tác trên CHÍNH VAI TRÒ: đóng lại thì không ai được cấp vai trò
 * đó nữa, nhưng những người đang giữ vẫn làm việc bình thường (§12.3.2). Hai
 * việc rất dễ bị nhầm nên giao diện phải nói thẳng sự khác biệt, không để người
 * dùng suy đoán.
 */
function RoleStatusSection() {
  const act = useAction();
  const [roleName, setRoleName] = useState(ASSIGNABLE_ROLES[1]);
  const [status, setStatus] = useState(RoleStatus.Inactive);

  // Hai vai trò hệ thống tự phụ thuộc — database sẽ từ chối (59904).
  const protectedRole = roleName === 'Customer' || roleName === 'Admin';

  return (
    <Panel
      title="Mở / đóng việc phân công một vai trò"
      tone="workflow"
      subtitle="Đóng một vai trò chỉ CHẶN VIỆC CẤP MỚI. Người đang giữ vai trò vẫn giữ nguyên quyền — muốn thu hồi của một người cụ thể thì dùng khối “Cấp và thu hồi vai trò” ở trên."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.put('/admin/roles/status', { roleName, status }),
            status === RoleStatus.Inactive
              ? `Đã đóng việc phân công vai trò ${roleName}. Người đang giữ vai trò không bị ảnh hưởng.`
              : `Đã mở lại việc phân công vai trò ${roleName}.`,
          );
        }}
      >
        <div className="field-grid">
          <Field label="Vai trò" required>
            <Select value={roleName} onChange={setRoleName} options={ASSIGNABLE_ROLES} />
          </Field>
          <Field label="Trạng thái" required>
            <Select
              value={status} onChange={setStatus}
              options={Object.values(RoleStatus)}
              labels={{ Active: 'Active — cho phép phân công', Inactive: 'Inactive — ngừng phân công' }}
            />
          </Field>
        </div>

        {protectedRole && status === RoleStatus.Inactive && (
          <div className="field-hint" style={{ color: 'var(--warning)', marginTop: '12px' }}>
            Không đóng được vai trò {roleName}: hệ thống tự cấp Customer khi có người đăng ký,
            và luôn phải còn ít nhất một Admin (UAI01). Database sẽ từ chối.
          </div>
        )}

        <button
          className={status === RoleStatus.Inactive ? 'btn-danger' : 'btn-primary'}
          style={{ marginTop: '16px' }}
          disabled={act.busy}
        >
          {act.busy ? 'Đang xử lý…' : status === RoleStatus.Inactive ? 'Đóng phân công' : 'Mở phân công'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Trạng thái tài khoản ────────────────────────────────────────────────── */

function UserStatusSection() {
  const act = useAction();
  const [userId, setUserId] = useState('');
  const [status, setStatus] = useState(UserStatus.Locked);

  return (
    <Panel
      title="Trạng thái tài khoản"
      tone="attention"
      subtitle="Khóa hoặc vô hiệu hóa một tài khoản. Tài khoản không ở trạng thái Active sẽ không đăng nhập được, và mọi phiên làm việc hiện có cũng mất hiệu lực."
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.patch(`/admin/users/${Number(userId)}/status`, { status }),
            `Đã chuyển tài khoản #${userId} sang ${ADMIN_STATUS_LABEL[status]}.`,
          );
        }}
      >
        <div className="field-grid">
          <Field label="UserID" required>
            <input type="number" min="1" value={userId} onChange={(e) => setUserId(e.target.value)} required />
          </Field>
          <Field label="Trạng thái mới" required>
            <Select value={status} onChange={setStatus}
                    options={Object.values(UserStatus)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>
        <button
          className={status === UserStatus.Active ? 'btn-primary' : 'btn-danger'}
          style={{ marginTop: '16px' }}
          disabled={act.busy || !userId}
        >
          {act.busy ? 'Đang lưu…' : 'Đổi trạng thái'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}

/* ── Phân công soát vé ───────────────────────────────────────────────────── */

function StaffAssignmentSection({ isAdmin }) {
  const { options: merged } = useConcertOptions();
  const act = useAction();

  const [staffId, setStaffId] = useState('');
  const [concertIds, setConcertIds] = useState('');
  const [status, setStatus] = useState(AssignmentStatus.Active);

  const parsed = concertIds
    .split(/[,\s]+/)
    .map((x) => Number(x.trim()))
    .filter((x) => Number.isInteger(x) && x > 0);
  const unique = [...new Set(parsed)];

  return (
    <Panel
      title="Phân công nhân viên soát vé"
      tone="workflow"
      subtitle={
        'Nhân viên chỉ soát được vé của concert mình được phân công — stored procedure trả về '
        + 'UNAUTHORIZED nếu quét vé của concert khác. Chọn trạng thái Revoked để thu hồi phân công.'
        + (isAdmin
          ? ''
          : ' Bạn chỉ phân công được cho concert do chính mình tổ chức; nếu danh sách có concert'
            + ' của người khác thì cả yêu cầu bị từ chối, không phân công một phần.')
      }
    >
      <form
        onSubmit={(e) => {
          e.preventDefault();
          act.run(
            () => api.post('/admin/checkin-staff-assignments', {
              staffUserId: Number(staffId),
              concertIds: unique,
              assignmentStatus: status,
            }),
            `Đã ${status === AssignmentStatus.Active ? 'phân công' : 'thu hồi'} `
            + `nhân viên #${staffId} cho ${unique.length} concert.`,
          );
        }}
      >
        <div className="field-grid">
          <Field label="UserID của nhân viên" hint="Người này phải đã có vai trò Check-in Staff." required>
            <input type="number" min="1" value={staffId} onChange={(e) => setStaffId(e.target.value)} required />
          </Field>
          <Field label="Trạng thái phân công" required>
            <Select value={status} onChange={setStatus}
                    options={Object.values(AssignmentStatus)} labels={ADMIN_STATUS_LABEL} />
          </Field>
        </div>

        <div style={{ marginTop: '16px' }}>
          <Field label="Danh sách ID concert" hint="Ngăn cách bằng dấu phẩy hoặc khoảng trắng." required>
            <textarea value={concertIds} onChange={(e) => setConcertIds(e.target.value)} placeholder="1, 2, 3" />
          </Field>
        </div>

        {merged.length > 0 && (
          <div style={{ marginTop: '12px', display: 'flex', flexWrap: 'wrap', gap: '6px' }}>
            {/* Chỉ Admin: danh sách gợi ý lấy từ GET /concerts (công khai, gồm concert của
                mọi Organizer) và không kèm thông tin sở hữu, nên client không thể lọc ra
                "concert của tôi". Với Organizer, "Chọn tất cả" gần như chắc chắn kéo theo
                concert của người khác và làm cả yêu cầu bị từ chối. */}
            {isAdmin && (
              <button
                type="button" className="btn-outline"
                style={{ padding: '4px 12px', fontSize: '0.75rem' }}
                onClick={() => setConcertIds(merged.map((c) => c.id).join(', '))}
              >
                Chọn tất cả ({merged.length})
              </button>
            )}
            {merged.slice(0, 20).map((c) => (
              <button
                key={c.id} type="button" className="id-pill"
                style={{ cursor: 'pointer' }}
                onClick={() => setConcertIds((v) => (v.trim() ? `${v.trim()}, ${c.id}` : String(c.id)))}
              >
                #{c.id} · {c.name}
              </button>
            ))}
          </div>
        )}

        <div className="field-hint" style={{ marginTop: '12px' }}>
          {unique.length > 0 ? `Sẽ gửi ${unique.length} concert.` : 'Chưa chọn concert nào.'}
        </div>

        <button className="btn-primary" style={{ marginTop: '16px' }} disabled={act.busy || !staffId || unique.length === 0}>
          {act.busy ? 'Đang lưu…' : 'Lưu phân công'}
        </button>
        <Banner state={act.state} />
      </form>
    </Panel>
  );
}
