import { createContext, useContext, useEffect, useMemo, useState, useCallback } from 'react';
import api, { bootstrapSession, setAccessToken, onAuthChange } from '../api/client';

/**
 * Trạng thái đăng nhập dùng chung.
 *
 * Bản trước không hề có khái niệm "người dùng" hay "vai trò": nó chỉ giữ một biến boolean
 * suy ra từ việc access token có tồn tại hay không. Vì thế trang Check-in — vốn yêu cầu
 * role 'Check-in Staff' — vẫn hiện trên thanh điều hướng cho mọi khách, và mọi route đều
 * vào được khi chưa đăng nhập; người dùng chỉ phát hiện ra khi nhận 401/403.
 *
 * Vai trò được đọc từ chính access token: backend đưa từng role vào một claim
 * ClaimTypes.Role, tuần tự hóa thành
 * "http://schemas.microsoft.com/ws/2008/06/identity/claims/role".
 */
const AuthContext = createContext(null);

const ROLE_CLAIM = 'http://schemas.microsoft.com/ws/2008/06/identity/claims/role';
const SUB_CLAIM = 'sub';

/**
 * Giải mã phần payload của JWT. KHÔNG xác minh chữ ký — và không cần: chữ ký chỉ có ý
 * nghĩa ở phía máy chủ. Ở client, payload chỉ dùng để quyết định hiển thị gì; mọi quyết
 * định về quyền hạn đều do backend và stored procedure thi hành.
 */
function decodeJwt(token) {
  if (!token) return null;
  try {
    const payload = token.split('.')[1];
    if (!payload) return null;
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    const json = decodeURIComponent(
      atob(base64)
        .split('')
        .map((c) => '%' + c.charCodeAt(0).toString(16).padStart(2, '0'))
        .join(''),
    );
    return JSON.parse(json);
  } catch {
    return null;
  }
}

function readIdentity(token) {
  const claims = decodeJwt(token);
  if (!claims) return null;

  const rawRoles = claims[ROLE_CLAIM] ?? claims.role ?? [];
  const roles = Array.isArray(rawRoles) ? rawRoles : [rawRoles];

  return {
    userId: Number(claims[SUB_CLAIM] ?? claims.nameid ?? 0) || null,
    displayName: claims.displayName ?? null,
    email: claims.email ?? null,
    roles: roles.filter(Boolean),
  };
}

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  // `initialising` phân biệt "chưa biết" với "chưa đăng nhập". Thiếu nó, mọi route được
  // bảo vệ sẽ chớp sang trang đăng nhập trong khoảnh khắc trước khi phiên được khôi phục.
  const [initialising, setInitialising] = useState(true);

  useEffect(() => {
    let alive = true;

    // Đồng bộ khi token đổi từ nơi khác (interceptor refresh, đăng xuất).
    const unsubscribe = onAuthChange((token) => {
      if (alive) setUser(readIdentity(token));
    });

    bootstrapSession()
      .then((token) => {
        if (alive) setUser(readIdentity(token));
      })
      .finally(() => {
        if (alive) setInitialising(false);
      });

    const onForcedLogout = () => alive && setUser(null);
    window.addEventListener('auth:logout', onForcedLogout);

    return () => {
      alive = false;
      unsubscribe();
      window.removeEventListener('auth:logout', onForcedLogout);
    };
  }, []);

  const login = useCallback(async (username, password) => {
    const res = await api.post('/auth/login', { username, password });
    setAccessToken(res.data.accessToken);
    setUser(readIdentity(res.data.accessToken));
  }, []);

  const register = useCallback(async (payload) => {
    const res = await api.post('/auth/register', payload);
    setAccessToken(res.data.accessToken);
    setUser(readIdentity(res.data.accessToken));
  }, []);

  const logout = useCallback(async () => {
    try {
      await api.post('/auth/logout');
    } catch {
      // Phiên có thể đã hết hạn ở phía máy chủ — vẫn phải xóa trạng thái ở client.
    }
    setAccessToken(null);
    setUser(null);
  }, []);

  const value = useMemo(
    () => ({
      user,
      initialising,
      isAuthenticated: !!user,
      hasRole: (role) => !!user?.roles?.includes(role),
      hasAnyRole: (...roles) => !!user?.roles?.some((r) => roles.includes(r)),
      login,
      register,
      logout,
    }),
    [user, initialising, login, register, logout],
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth phải được dùng bên trong <AuthProvider>.');
  return ctx;
}
