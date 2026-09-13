import { useState } from 'react';
import { useNavigate, useLocation, Link } from 'react-router-dom';
import { useAuth } from '../auth/AuthContext';
import { apiError } from '../api/client';
import { Button, Card, Alert, Field, Input, Tabs } from '../components/ui';
import { IconTicket, IconArrowRight, IconEye, IconEyeOff } from '../components/ui/icons';

const EMPTY = { username: '', password: '', email: '', displayName: '' };

/**
 * Đăng nhập và đăng ký.
 *
 * Hai chế độ dùng CHUNG một form thay vì hai trang riêng: người dùng gõ nhầm
 * chỗ rồi mới nhận ra mình chưa có tài khoản là chuyện thường, và bắt họ điều
 * hướng sang trang khác rồi gõ lại từ đầu là ma sát không cần thiết. Chuyển tab
 * giữ nguyên username và password đã nhập.
 *
 * Yêu cầu mật khẩu được nêu TRƯỚC khi gõ, không phải sau khi bị máy chủ từ chối.
 * Chúng khớp đúng RegisterValidator ở backend: tối thiểu 8 ký tự, có chữ hoa,
 * có chữ số.
 */
export default function Auth() {
  const [isLogin, setIsLogin] = useState(true);
  const [form, setForm] = useState(EMPTY);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  // Ẩn theo mặc định — dùng chung cho cả đăng nhập và đăng ký vì hai chế độ
  // dùng chung một ô mật khẩu (xem comment đầu file).
  const [showPassword, setShowPassword] = useState(false);

  const { login, register } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  // Quay lại đúng trang người dùng định vào trước khi bị chặn
  // (RequireAuth ghi lại trong location.state.from).
  const redirectTo = location.state?.from?.pathname ?? '/';

  const set = (k) => (e) => setForm((f) => ({ ...f, [k]: e.target.value }));

  const handleSubmit = async (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    try {
      if (isLogin) {
        await login(form.username, form.password);
      } else {
        await register({
          username: form.username,
          password: form.password,
          email: form.email,
          displayName: form.displayName,
        });
      }
      navigate(redirectTo, { replace: true });
    } catch (err) {
      setError(apiError(err, isLogin ? 'Đăng nhập không thành công.' : 'Đăng ký không thành công.'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="container" style={{ maxWidth: 420, paddingTop: 'var(--space-10)' }}>
      <div className="stack gap-2" style={{ alignItems: 'center', marginBottom: 'var(--space-8)' }}>
        <span className="nav__mark" style={{ width: 40, height: 40, borderRadius: 'var(--radius-lg)' }}>
          <IconTicket size={20} />
        </span>
        <h1 style={{ fontSize: 'var(--text-2xl)' }}>
          {isLogin ? 'Đăng nhập' : 'Tạo tài khoản'}
        </h1>
        <p className="text-sm text-secondary" style={{ textAlign: 'center' }}>
          {isLogin
            ? 'Đăng nhập để giữ chỗ, thanh toán và xem vé của bạn.'
            : 'Tạo tài khoản để bắt đầu đặt vé.'}
        </p>
      </div>

      <Card>
        <div className="card__header" style={{ paddingBottom: 0, borderBottom: 'none' }}>
          <Tabs
            value={isLogin ? 'login' : 'register'}
            onChange={(v) => { setIsLogin(v === 'login'); setError(''); }}
            items={[
              { value: 'login', label: 'Đăng nhập' },
              { value: 'register', label: 'Đăng ký' },
            ]}
          />
        </div>

        <form className="card__body stack gap-4" onSubmit={handleSubmit}>
          {error && <Alert tone="danger">{error}</Alert>}

          <Field label="Tên đăng nhập" required>
            {(a) => (
              <Input
                {...a}
                value={form.username}
                onChange={set('username')}
                autoComplete="username"
                autoCapitalize="none"
                spellCheck={false}
                required
              />
            )}
          </Field>

          {!isLogin && (
            <>
              <Field label="Email" required>
                {(a) => (
                  <Input {...a} type="email" value={form.email} onChange={set('email')}
                         autoComplete="email" required />
                )}
              </Field>
              <Field label="Tên hiển thị" required>
                {(a) => (
                  <Input {...a} value={form.displayName} onChange={set('displayName')}
                         autoComplete="name" required />
                )}
              </Field>
            </>
          )}

          <Field
            label="Mật khẩu"
            required
            hint={isLogin ? undefined : 'Tối thiểu 8 ký tự, có ít nhất 1 chữ hoa và 1 chữ số.'}
          >
            {(a) => (
              <div style={{ position: 'relative' }}>
                <Input
                  {...a}
                  type={showPassword ? 'text' : 'password'}
                  value={form.password}
                  onChange={set('password')}
                  autoComplete={isLogin ? 'current-password' : 'new-password'}
                  required
                  minLength={isLogin ? undefined : 8}
                  style={{ paddingRight: 'var(--space-10)' }}
                />
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => setShowPassword((v) => !v)}
                  aria-label={showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu'}
                  icon={showPassword ? <IconEyeOff size={16} /> : <IconEye size={16} />}
                  style={{
                    position: 'absolute', right: 'var(--space-1)', top: '50%',
                    transform: 'translateY(-50%)',
                  }}
                />
              </div>
            )}
          </Field>

          <Button
            type="submit" variant="primary" size="lg" block
            loading={loading}
            iconEnd={<IconArrowRight size={16} />}
          >
            {isLogin ? 'Đăng nhập' : 'Tạo tài khoản'}
          </Button>
        </form>
      </Card>

      <p className="text-xs text-muted" style={{ textAlign: 'center', marginTop: 'var(--space-5)' }}>
        Endpoint xác thực giới hạn 5 yêu cầu mỗi phút để chống dò mật khẩu.
        Nếu bị chặn tạm thời, chờ một lát rồi thử lại.
      </p>

      <p className="text-sm text-secondary" style={{ textAlign: 'center', marginTop: 'var(--space-3)' }}>
        <Link to="/" style={{ textDecoration: 'underline' }}>Quay lại danh sách sự kiện</Link>
      </p>
    </div>
  );
}
