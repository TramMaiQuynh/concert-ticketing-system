import { useEffect, useState } from 'react';
import { BrowserRouter, Routes, Route, Link, NavLink, Navigate, useNavigate, useLocation } from 'react-router-dom';
import './index.css';
import { AuthProvider, useAuth } from './auth/AuthContext';
import { ThemeProvider, ThemeToggle } from './theme/ThemeProvider';
import { ToastProvider, useToast } from './components/ui/Toast';
import { Button } from './components/ui';
import { IconTicket, IconMenu, IconX, IconLogout } from './components/ui/icons';
import RequireAuth from './components/RequireAuth';
import { Role } from './domain/enums';
import Auth from './pages/Auth';
import Home from './pages/Home';
import Concert from './pages/Concert';
import Checkout from './pages/Checkout';
import MyBookings from './pages/MyBookings';
import PaymentSimulator from './pages/PaymentSimulator';
import StaffCheckIn from './pages/StaffCheckIn';
import AdminLayout from './pages/admin/AdminLayout';

/** Các mục điều hướng mà vai trò hiện tại thực sự dùng được. */
function useNavItems() {
  const { hasRole } = useAuth();
  return [
    { to: '/', label: 'Sự kiện', end: true },
    hasRole(Role.Customer) && { to: '/my-bookings', label: 'Vé của tôi' },
    hasRole(Role.CheckInStaff) && { to: '/checkin', label: 'Soát vé' },
    (hasRole(Role.Admin) || hasRole(Role.Organizer)) && { to: '/admin', label: 'Quản trị' },
  ].filter(Boolean);
}

function Navbar() {
  const { isAuthenticated, user, logout } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const items = useNavItems();
  const [open, setOpen] = useState(false);

  // Đóng menu mỗi khi chuyển trang — nếu không, người dùng bấm một mục xong
  // vẫn thấy menu che nội dung vừa mở.
  useEffect(() => { setOpen(false); }, [location.pathname]);

  const handleLogout = async () => {
    await logout();
    navigate('/');
  };

  return (
    <>
      <header className="nav">
        <div className="nav__inner">
          <Link to="/" className="nav__brand" aria-label="StagePass — trang chủ">
            <span className="nav__mark"><IconTicket size={15} /></span>
            StagePass
          </Link>

          <nav className="nav__links" aria-label="Điều hướng chính">
            {items.map((it) => (
              <NavLink
                key={it.to}
                to={it.to}
                end={it.end}
                className={({ isActive }) => `nav__link${isActive ? ' is-active' : ''}`}
              >
                {it.label}
              </NavLink>
            ))}
          </nav>

          <span className="nav__spacer" />

          <div className="nav__end">
            <ThemeToggle />
            {isAuthenticated ? (
              <>
                <span className="nav__user-name text-sm text-secondary">
                  {user?.displayName ?? `#${user?.userId}`}
                </span>
                <Button size="sm" variant="ghost" onClick={handleLogout} aria-label="Đăng xuất" title="Đăng xuất">
                  <IconLogout size={16} />
                </Button>
              </>
            ) : (
              <Button size="sm" variant="primary" onClick={() => navigate('/login')}>
                Đăng nhập
              </Button>
            )}
            <Button
              className="nav__burger"
              size="sm"
              variant="ghost"
              onClick={() => setOpen((v) => !v)}
              aria-label={open ? 'Đóng menu' : 'Mở menu'}
              aria-expanded={open}
            >
              {open ? <IconX size={17} /> : <IconMenu size={17} />}
            </Button>
          </div>
        </div>
      </header>

      {open && (
        <nav className="nav-drawer" aria-label="Điều hướng">
          {items.map((it) => (
            <NavLink
              key={it.to}
              to={it.to}
              end={it.end}
              className={({ isActive }) => `nav__link${isActive ? ' is-active' : ''}`}
            >
              {it.label}
            </NavLink>
          ))}
        </nav>
      )}
    </>
  );
}

/**
 * Giới hạn tần suất (HTTP 429).
 *
 * `client.js` phát ra sự kiện `api:ratelimit`; ở đây chuyển thành toast. Trước
 * đây khối này tự dựng một băng cố định riêng — nghĩa là ứng dụng có hai cơ chế
 * thông báo song song, đặt ở hai vị trí khác nhau, trông không liên quan gì nhau.
 */
function RateLimitBridge() {
  const toast = useToast();
  useEffect(() => {
    const onLimit = (e) => toast(e.detail, { type: 'warning' });
    window.addEventListener('api:ratelimit', onLimit);
    return () => window.removeEventListener('api:ratelimit', onLimit);
  }, [toast]);
  return null;
}

export default function App() {
  return (
    <ThemeProvider>
      <ToastProvider>
        <BrowserRouter>
          <AuthProvider>
            <div className="app">
              <Navbar />
              <RateLimitBridge />

              <main className="page">
                <Routes>
                  <Route path="/" element={<Home />} />
                  <Route path="/login" element={<Auth />} />
                  <Route path="/concert/:id" element={<Concert />} />

                  {/* Đặt vé và thanh toán là nghiệp vụ của Customer — backend cũng chỉ
                      cho role Customer gọi (BookingController, PaymentController). */}
                  <Route
                    path="/checkout/:bookingId"
                    element={<RequireAuth roles={[Role.Customer]}><Checkout /></RequireAuth>}
                  />
                  {/* Trang mô phỏng cổng thanh toán — chỉ có tác dụng khi backend chạy ở
                      chế độ PaymentGateway:Mode = "Simulator"; ngoài chế độ đó backend trả 404. */}
                  <Route
                    path="/payment-simulator/:bookingId/:paymentId"
                    element={<RequireAuth roles={[Role.Customer]}><PaymentSimulator /></RequireAuth>}
                  />
                  <Route
                    path="/my-bookings"
                    element={<RequireAuth roles={[Role.Customer]}><MyBookings /></RequireAuth>}
                  />
                  <Route
                    path="/checkin"
                    element={<RequireAuth roles={[Role.CheckInStaff]}><StaffCheckIn /></RequireAuth>}
                  />

                  {/* Khu quản trị tự định tuyến bên trong; "/*" để các mục con hoạt động.
                      Chặn ở đây chỉ là trải nghiệm — backend và stored procedure mới là nơi
                      thi hành quyền thật (sp_AssignRole tự chặn không phải Admin bằng 58401). */}
                  <Route
                    path="/admin/*"
                    element={<RequireAuth roles={[Role.Admin, Role.Organizer]}><AdminLayout /></RequireAuth>}
                  />

                  <Route path="*" element={<Navigate to="/" replace />} />
                </Routes>
              </main>
            </div>
          </AuthProvider>
        </BrowserRouter>
      </ToastProvider>
    </ThemeProvider>
  );
}
