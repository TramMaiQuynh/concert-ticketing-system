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

  const items = [
    { to: 'concerts', label: 'Concert', desc: 'Vòng đời, hạng vé, kho ghế' },
    { to: 'catalog', label: 'Danh mục', desc: 'Nghệ sĩ, địa điểm, khu vực, ghế' },
    // Chỉ Admin: sp_ConfigureVenueMap / sp_CreateZone / sp_CreateSeat đều tự chặn
    // vai trò khác ở tầng database, nên hiện mục này cho Organizer chỉ dẫn họ vào
    // một trang chắc chắn trả 403.
    ...(isAdmin ? [{ to: 'venue-map', label: 'Sơ đồ địa điểm', desc: 'Mặt phẳng, sân khấu, khu, ghế' }] : []),
    { to: 'promotions', label: 'Khuyến mãi', desc: 'Chương trình và mã giảm giá' },
    { to: 'refunds', label: 'Hoàn tiền', desc: 'Hủy đơn và xác nhận hoàn' },
    ...(isAdmin ? [{ to: 'users', label: 'Người dùng', desc: 'Vai trò, khóa tài khoản, soát vé' }] : []),
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
          <Route index element={<Navigate to="concerts" replace />} />
          <Route path="concerts" element={<Concerts />} />
          <Route path="catalog" element={<Catalog isAdmin={isAdmin} />} />
          <Route
            path="venue-map"
            element={isAdmin ? <VenueMap /> : <Navigate to="../concerts" replace />}
          />
          <Route path="promotions" element={<Promotions />} />
          <Route path="refunds" element={<Refunds />} />
          <Route
            path="users"
            element={isAdmin ? <Users /> : <Navigate to="../concerts" replace />}
          />
          <Route path="*" element={<Navigate to="concerts" replace />} />
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
