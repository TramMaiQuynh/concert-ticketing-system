import { Navigate, useLocation } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { Card, EmptyState, Skeleton } from './ui';

/**
 * Chặn route ở phía giao diện.
 *
 * Đây CHỈ là trải nghiệm người dùng, không phải lớp bảo mật: mọi quyết định thật sự do
 * backend ([Authorize]) và stored procedure (@ActorUserID) thi hành — theo UAI04, phân
 * quyền là trách nhiệm của tầng ứng dụng phía máy chủ. Mục đích ở đây là không dẫn người
 * dùng vào một trang chắc chắn sẽ trả 401/403, và không hiển thị lối vào những khu vực
 * họ không có quyền.
 */
export default function RequireAuth({ roles, children }) {
  const { isAuthenticated, initialising, hasAnyRole } = useAuth();
  const location = useLocation();

  // Chưa biết trạng thái phiên (đang đổi refresh cookie lấy access token). Nếu điều
  // hướng ngay lúc này, người dùng đã đăng nhập sẽ bị đá về trang đăng nhập mỗi lần F5.
  if (initialising) {
    // Khung xương thay cho chữ "Đang tải": người dùng thấy bố cục sắp hiện ra,
    // và trang không nhảy khi nội dung thật thay vào.
    return (
      <div className="container stack gap-4" style={{ maxWidth: 640, paddingTop: 'var(--space-10)' }}>
        <Skeleton w="40%" h={30} />
        <Skeleton w="100%" h={180} r="var(--radius-xl)" />
        <span className="sr-only">Đang khôi phục phiên đăng nhập…</span>
      </div>
    );
  }

  if (!isAuthenticated) {
    // Ghi lại nơi muốn đến để quay lại sau khi đăng nhập.
    return <Navigate to="/login" replace state={{ from: location }} />;
  }

  if (roles?.length && !hasAnyRole(...roles)) {
    return (
      <div className="container" style={{ maxWidth: 520 }}>
        <Card>
          <EmptyState title="Không đủ quyền truy cập">
            Trang này dành cho vai trò: {roles.join(', ')}.
          </EmptyState>
        </Card>
      </div>
    );
  }

  return children;
}
