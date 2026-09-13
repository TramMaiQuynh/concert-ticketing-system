import { useState } from 'react';
import { NavLink, Navigate, Routes, Route } from 'react-router-dom';
import { useAuth } from '../../auth/AuthContext';
import { Role } from '../../domain/enums';
import { clearAllCatalog } from '../../lib/localCatalog';
import { Button, Card, EmptyState, ConfirmDialog } from '../../components/ui';
import Catalog from './Catalog';
import VenueMap from './VenueMap';
import Concerts from './Concerts';
import Promotions from './Promotions';
import Users from './Users';
import Refunds from './Refunds';
import Reports from './Reports';
import Audit from './Audit';

/**
 * Khu quản trị.
 *
 * PHÂN QUYỀN Ở ĐÂY CHỈ LÀ TRẢI NGHIỆM, KHÔNG PHẢI BẢO MẬT. Quyết định thật nằm ở
 * `[Authorize]` của backend và ở kiểm tra @ActorUserID bên trong từng stored
 * procedure. Ẩn một mục chỉ để người dùng khỏi đi vào chỗ chắc chắn nhận 403.
 * Ví dụ rõ nhất: mục "Người dùng" gọi sp_AssignRole, mà stored procedure đó tự
 * chặn bằng lỗi 58401 nếu người gọi không phải Admin — kể cả khi thuộc tính
 * [Authorize] ở controller có rộng hơn.
 */
export default function AdminLayout() {
  const { hasRole } = useAuth();
  const [confirmClear, setConfirmClear] = useState(false);
  const isAdmin = hasRole(Role.Admin);
  const isOrganizer = hasRole(Role.Organizer);

  if (!isAdmin && !isOrganizer) {
    return (
      <div className="container" style={{ maxWidth: 520 }}>
        <Card>
          <EmptyState title="Không đủ quyền truy cập">
            Khu quản trị dành cho Admin và Organizer.
          </EmptyState>
        </Card>
      </div>
    );
  }

  // Tuyệt đối, không tương đối: khu này dựng bằng MỘT <Routes> con lồng bên
  // trong route cha "/admin/*" (App.jsx), không phải bằng <Outlet> của một cây
  // route cha-con thật. Với route cha dùng "*" (không tiền tố tĩnh), một `to`
  // tương đối như "concerts" không thay thế đoạn cuối của URL — nó bị NỐI THÊM
  // vào nguyên vẹn pathname hiện tại. Rơi vào Route path="*" bên dưới rồi lặp
  // lại là cách chuỗi "/admin/concerts/catalog/concerts/concerts/concerts/…"
  // dài vô hạn được sinh ra. Tuyệt đối hoá triệt tiêu toàn bộ sự mập mờ đó.
  const items = [
    { to: '/admin/concerts', label: 'Concert', desc: 'Vòng đời, hạng vé, kho ghế' },
    { to: '/admin/catalog', label: 'Danh mục', desc: 'Nghệ sĩ, địa điểm, khu vực, ghế' },
    // Chỉ Admin: sp_ConfigureVenueMap / sp_CreateZone / sp_CreateSeat đều tự chặn
    // vai trò khác ở tầng database, nên hiện mục này cho Organizer chỉ dẫn họ vào
    // một trang chắc chắn trả 403.
    ...(isAdmin ? [{ to: '/admin/venue-map', label: 'Sơ đồ địa điểm', desc: 'Mặt phẳng, sân khấu, khu, ghế' }] : []),
    { to: '/admin/promotions', label: 'Khuyến mãi', desc: 'Chương trình và mã giảm giá' },
    { to: '/admin/refunds', label: 'Hoàn tiền', desc: 'Hủy đơn và xác nhận hoàn' },
    { to: '/admin/reports', label: 'Báo cáo', desc: 'Doanh thu, check-in, người giữ vé, danh sách chờ' },
    // Chỉ Admin: VW_AuditTrail tự trả 0 dòng cho phiên không giữ Role Admin, nên hiện
    // mục này cho Organizer chỉ dẫn họ vào một trang chắc chắn rỗng.
    ...(isAdmin ? [{ to: '/admin/audit', label: 'Nhật ký', desc: 'Tra cứu lịch sử thay đổi (FR59)' }] : []),
    // Cả hai vai trò đều vào được, nhưng thấy khác nhau: Organizer chỉ có khối phân
    // công soát vé cho concert của mình (sp_AddCheckinStaffAssignment mở cho Organizer
    // sở hữu), còn cấp vai trò / khóa tài khoản vẫn là việc riêng của Admin. Nhãn đổi
    // theo vai trò để không hứa một trang "Người dùng" mà Organizer không quản trị được.
    {
      to: '/admin/users',
      label: isAdmin ? 'Người dùng' : 'Soát vé',
      desc: isAdmin ? 'Vai trò, khóa tài khoản, soát vé' : 'Phân công nhân viên soát vé',
    },
  ];

  return (
    <div className="container admin">
      <aside className="admin__side">
        <div className="overline" style={{ marginBottom: 'var(--space-3)' }}>Quản trị</div>

        <nav className="admin__nav" aria-label="Khu quản trị">
          {items.map((it) => (
            <NavLink key={it.to} to={it.to} className={({ isActive }) => (isActive ? 'active' : '')}>
              {it.label}
              <small>{it.desc}</small>
            </NavLink>
          ))}
        </nav>

        <div
          className="admin__note"
          style={{
            marginTop: 'var(--space-6)', padding: 'var(--space-3)',
            borderRadius: 'var(--radius-lg)', background: 'var(--surface-sunken)',
            border: '1px solid var(--border-subtle)',
          }}
        >
          <div className="overline" style={{ marginBottom: 'var(--space-2)' }}>Sổ tay cục bộ</div>
          <p className="text-xs text-muted" style={{ marginBottom: 'var(--space-3)' }}>
            API quản trị không có endpoint đọc nào, nên các ID vừa tạo được nhớ tạm trong
            trình duyệt này để những bước sau còn chọn được. Đổi máy là mất — nguồn sự
            thật vẫn là database.
          </p>
          <Button
            size="sm" block
            onClick={() => setConfirmClear(true)}
          >
            Dọn sổ tay
          </Button>
        </div>
      </aside>

      <main style={{ minWidth: 0 }}>
        <Routes>
          <Route index element={<Navigate to="/admin/concerts" replace />} />
          <Route path="concerts" element={<Concerts />} />
          <Route path="catalog" element={<Catalog isAdmin={isAdmin} />} />
          <Route
            path="venue-map"
            element={isAdmin ? <VenueMap /> : <Navigate to="/admin/concerts" replace />}
          />
          <Route path="promotions" element={<Promotions />} />
          <Route path="refunds" element={<Refunds />} />
          <Route path="reports" element={<Reports />} />
          <Route
            path="audit"
            element={isAdmin ? <Audit /> : <Navigate to="/admin/concerts" replace />}
          />
          <Route path="users" element={<Users isAdmin={isAdmin} />} />
          <Route path="*" element={<Navigate to="/admin/concerts" replace />} />
        </Routes>
      </main>

      <ConfirmDialog
        open={confirmClear}
        onClose={() => setConfirmClear(false)}
        onConfirm={() => { clearAllCatalog(); setConfirmClear(false); }}
        title="Dọn sổ tay cục bộ?"
        confirmText="Xoá sổ tay"
        danger
      >
        Xoá toàn bộ ID đã ghi nhớ trong trình duyệt này. Dữ liệu trong database KHÔNG
        bị ảnh hưởng — chỉ mất danh sách gợi ý, và bạn vẫn nhập ID thủ công được.
      </ConfirmDialog>
    </div>
  );
}
