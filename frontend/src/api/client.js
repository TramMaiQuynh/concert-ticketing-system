import axios from 'axios';

/**
 * Client HTTP dùng chung.
 *
 * Mặc định dùng cùng origin. Vite proxy tiếp /api tới backend trong lúc phát triển,
 * nhờ đó refresh cookie luôn thuộc cùng host với trang đang mở (localhost, 127.0.0.1
 * hoặc địa chỉ LAN). Triển khai tách frontend/backend đặt VITE_API_BASE_URL tuyệt đối.
 */
const BASE_URL = import.meta.env.VITE_API_BASE_URL ?? '/api';

const api = axios.create({
  baseURL: BASE_URL,
  // Bắt buộc: refresh token nằm trong HttpOnly Cookie, không đọc được từ JavaScript.
  withCredentials: true,
});

// ── Access token: giữ trong bộ nhớ, KHÔNG lưu localStorage ──────────────────
// Access token nằm trong biến của module (mất khi tải lại trang) là cố ý — lưu vào
// localStorage sẽ khiến bất kỳ lỗi XSS nào cũng đánh cắp được token. Phiên đăng nhập
// được khôi phục sau khi tải lại trang bằng refresh cookie (xem bootstrapSession).
let accessToken = null;
const subscribers = new Set();

export function setAccessToken(token) {
  accessToken = token;
  // Đây là điểm DUY NHẤT biết phiên bắt đầu hay kết thúc (đăng nhập, đăng xuất,
  // refresh, và cả khi interceptor xoá token). Đặt cờ ở đây thay vì rải ra từng
  // chỗ gọi, để không bao giờ có đường nào quên cập nhật.
  markSession(!!token);
  subscribers.forEach((fn) => fn(token));
}

export function getAccessToken() {
  return accessToken;
}

/** Đăng ký nhận thông báo khi access token đổi (đăng nhập / đăng xuất / refresh). */
export function onAuthChange(fn) {
  subscribers.add(fn);
  return () => subscribers.delete(fn);
}

api.interceptors.request.use((config) => {
  if (accessToken) config.headers.Authorization = `Bearer ${accessToken}`;
  return config;
});

// ── Refresh: MỘT lượt duy nhất tại một thời điểm ────────────────────────────
/**
 * Đây là điểm quan trọng nhất của file này.
 *
 * Backend áp dụng refresh token rotation KÈM phát hiện tái sử dụng: mỗi lần refresh sẽ
 * thu hồi token cũ, và nếu một token ĐÃ THU HỒI được trình lại thì toàn bộ chuỗi token
 * của người dùng bị thu hồi (phản ứng chuẩn với nghi vấn đánh cắp token).
 *
 * Bản trước gọi refresh độc lập trong từng response interceptor. Khi trang tải nhiều
 * request song song (Concert.jsx gọi đồng thời chi tiết concert và sơ đồ ghế), cả hai
 * cùng nhận 401 và cùng gọi refresh: lượt thứ hai trình lại đúng cái token vừa bị lượt
 * đầu thu hồi → backend coi là token bị dùng lại → thu hồi sạch chuỗi token → người
 * dùng bị đăng xuất giữa chừng dù không có gì bất thường.
 *
 * Vì vậy mọi lời gọi refresh phải gộp về một lượt duy nhất; các request khác chờ đúng
 * lượt đó rồi dùng chung kết quả.
 */
let refreshPromise = null;

function refreshSession() {
  if (!refreshPromise) {
    refreshPromise = axios
      .post(`${BASE_URL}/auth/refresh`, {}, { withCredentials: true })
      .then((res) => {
        const token = res.data?.accessToken ?? null;
        setAccessToken(token);
        return token;
      })
      .catch((err) => {
        setAccessToken(null);
        throw err;
      })
      .finally(() => {
        refreshPromise = null;
      });
  }
  return refreshPromise;
}

/**
 * DẤU HIỆU CÓ PHIÊN.
 *
 * Refresh token nằm trong cookie HttpOnly nên JavaScript KHÔNG đọc được — đó là
 * điều đúng về mặt bảo mật, nhưng kéo theo một hệ quả: trang không có cách nào
 * biết mình có đang đăng nhập hay không trước khi hỏi máy chủ.
 *
 * Hệ quả thực tế đo được: MỌI lượt truy cập ẩn danh đều gọi `/auth/refresh`, nhận
 * 401, và trình duyệt ghi một dòng lỗi đỏ vào console. Một request lãng phí trên
 * mỗi lượt xem trang, cộng thêm nhiễu che mất lỗi thật khi cần chẩn đoán.
 *
 * Cách xử lý: khi đăng nhập thành công thì đặt một cờ trong localStorage. Cờ này
 * KHÔNG phải thông tin bí mật và KHÔNG cấp quyền gì — nó chỉ trả lời câu hỏi
 * "có đáng gọi refresh không". Quyền vẫn hoàn toàn do cookie HttpOnly và chữ ký
 * JWT quyết định; giả mạo cờ này chỉ khiến trình duyệt gọi một request rồi nhận
 * 401 như cũ.
 */
const SESSION_HINT = 'ct.hasSession';

function markSession(active) {
  try {
    if (active) localStorage.setItem(SESSION_HINT, '1');
    else localStorage.removeItem(SESSION_HINT);
  } catch { /* chế độ riêng tư chặn localStorage — chỉ mất tối ưu, không mất chức năng */ }
}

function maybeHasSession() {
  try {
    return localStorage.getItem(SESSION_HINT) === '1';
  } catch {
    // Không đọc được thì cứ thử refresh: thà một request thừa còn hơn đá người
    // dùng đang đăng nhập ra ngoài.
    return true;
  }
}

/**
 * Khôi phục phiên khi tải lại trang: thử đổi refresh cookie lấy access token mới.
 * Không có bước này thì sau mỗi lần F5, giao diện hiển thị như đã đăng xuất cho tới
 * khi có một request bị 401 — người dùng thấy nút "Đăng nhập" dù phiên vẫn còn hiệu lực.
 *
 * Bỏ qua hẳn lời gọi khi chưa từng đăng nhập trên trình duyệt này.
 */
export async function bootstrapSession() {
  if (!maybeHasSession()) return null;
  try {
    return await refreshSession();
  } catch {
    markSession(false);
    return null; // cookie đã hết hạn hoặc bị thu hồi — trạng thái hợp lệ
  }
}

/** Các endpoint không được phép kích hoạt vòng lặp refresh. */
const NO_REFRESH = ['/auth/login', '/auth/register', '/auth/refresh', '/auth/logout'];

api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const original = error.config;
    const status = error.response?.status;

    if (status === 429) {
      window.dispatchEvent(
        new CustomEvent('api:ratelimit', {
          detail: 'Bạn thao tác quá nhanh. Vui lòng chờ một lát rồi thử lại.',
        }),
      );
    }

    const path = original?.url ?? '';
    const refreshable =
      status === 401 && original && !original._retry && !NO_REFRESH.some((p) => path.startsWith(p));

    if (!refreshable) return Promise.reject(error);

    original._retry = true;
    try {
      const token = await refreshSession();
      if (!token) throw error;
      original.headers = original.headers ?? {};
      original.headers.Authorization = `Bearer ${token}`;
      return api(original);
    } catch (refreshError) {
      window.dispatchEvent(new Event('auth:logout'));
      return Promise.reject(refreshError);
    }
  },
);

// ── Đọc lỗi ─────────────────────────────────────────────────────────────────
/**
 * Backend trả lỗi theo RFC 7807 (`application/problem+json`) qua
 * ErrorHandlingMiddleware, còn lỗi validate của FluentValidation trả
 * ValidationProblemDetails với object `errors`. Gom về một chỗ để mọi trang hiển thị
 * thông điệp giống nhau thay vì mỗi trang tự dò `detail || message || Message || ...`.
 */
export function apiError(err, fallback = 'Đã có lỗi xảy ra. Vui lòng thử lại.') {
  const data = err?.response?.data;

  if (data?.errors && typeof data.errors === 'object') {
    const messages = Object.values(data.errors).flat().filter(Boolean);
    if (messages.length) return messages.join(' ');
  }
  if (typeof data?.detail === 'string' && data.detail) return data.detail;
  if (typeof data?.title === 'string' && data.title) return data.title;
  if (typeof data === 'string' && data) return data;
  if (err?.response?.status === 401) return 'Bạn cần đăng nhập để thực hiện thao tác này.';
  if (err?.response?.status === 403) return 'Bạn không có quyền thực hiện thao tác này.';
  if (err?.code === 'ERR_NETWORK') return 'Không kết nối được máy chủ. Kiểm tra lại kết nối mạng.';
  return fallback;
}

export default api;
