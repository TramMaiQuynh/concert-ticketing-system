import { createContext, useContext, useEffect, useState, useCallback } from 'react';
import { IconSun, IconMoon } from '../components/ui/icons';
import { Button } from '../components/ui';

/**
 * Theme sáng / tối.
 *
 * Ba trạng thái, không phải hai: 'light', 'dark', và 'system' (mặc định).
 * 'system' là mặc định đúng — người dùng đã cấu hình sở thích ở tầng hệ điều
 * hành rồi, ứng dụng không nên tự quyết thay.
 *
 * Lựa chọn tường minh được ghi vào localStorage và đặt thành `data-theme` trên
 * <html>. CSS ưu tiên `data-theme` hơn `prefers-color-scheme`, nên lựa chọn của
 * người dùng luôn thắng cài đặt máy.
 *
 * CHỚP TRẮNG KHI TẢI TRANG: một script nhỏ trong index.html đặt `data-theme`
 * TRƯỚC khi React chạy. Nếu chỉ đặt ở đây, trang sẽ hiện nền trắng một nhịp rồi
 * mới chuyển tối — lỗi mà gần như mọi bản tự làm dark mode đều mắc.
 */

const KEY = 'ct.theme';
const ThemeContext = createContext({ theme: 'system', setTheme: () => {} });

function apply(theme) {
  const root = document.documentElement;
  if (theme === 'system') root.removeAttribute('data-theme');
  else root.setAttribute('data-theme', theme);
}

export function ThemeProvider({ children }) {
  const [theme, setThemeState] = useState(() => {
    try { return localStorage.getItem(KEY) ?? 'system'; } catch { return 'system'; }
  });

  useEffect(() => { apply(theme); }, [theme]);

  const setTheme = useCallback((next) => {
    setThemeState(next);
    try {
      if (next === 'system') localStorage.removeItem(KEY);
      else localStorage.setItem(KEY, next);
    } catch { /* chế độ riêng tư chặn localStorage — theme vẫn đổi cho phiên này */ }
  }, []);

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  );
}

export function useTheme() { return useContext(ThemeContext); }

/**
 * Nút đổi theme. Vòng qua sáng → tối → theo hệ thống.
 *
 * Icon hiển thị theme SẼ chuyển sang khi bấm, kèm `title` nói rõ trạng thái hiện
 * tại — nếu chỉ hiện icon, người dùng không đoán được đang ở chế độ nào,
 * đặc biệt khi đang ở 'system' mà máy đang để sáng.
 */
export function ThemeToggle() {
  const { theme, setTheme } = useTheme();
  const next = theme === 'light' ? 'dark' : theme === 'dark' ? 'system' : 'light';
  const label = { light: 'Đang dùng giao diện sáng', dark: 'Đang dùng giao diện tối', system: 'Đang theo cài đặt hệ thống' }[theme];

  return (
    <Button
      variant="ghost"
      size="sm"
      onClick={() => setTheme(next)}
      aria-label={`${label}. Bấm để chuyển.`}
      title={label}
    >
      {theme === 'dark' ? <IconMoon size={16} /> : <IconSun size={16} />}
    </Button>
  );
}
