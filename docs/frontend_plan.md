# Kế Hoạch Xây Dựng Frontend — Concert Ticketing System
*Production-grade Frontend cho Thin Backend (ASP.NET Core 9) + Thick Database (SQL Server)*
*Version 1.0 — Authoritative. Khớp 100% endpoints hiện có của backend.*

> [!IMPORTANT]
> Nguyên tắc cốt lõi: **Frontend không chứa business rule, không chứa quyết định phân quyền.**
> Backend/Database là nơi duy nhất enforce quyền (RBAC qua DB principal + kiểm tra vai trò trong
> từng Stored Procedure). Frontend chỉ: (1) Xác thực & hiển thị UI theo role, (2) Gọi API, (3) Render dữ liệu.
> Tương ứng "Dynamic reconfiguration of user interfaces based on authorization" (OWASP Access Control).

---

## 1. Kiến Trúc Tổng Thể

```
[ Browser ]
      |  HTTPS / http://localhost:5295
      v
[ React 19 SPA (Vite) ]          <- frontend/src
  axios instance (Bearer JWT + HttpOnly refresh cookie)
  AuthContext (user, role, login/logout)
  RoleRoute guard (Admin / Organizer / Customer / Check-in Staff)
         |
         v
[ ASP.NET Core 9 Web API ]       <- backend (33 endpoints)
  Controllers (Admin, Auth, Booking, CheckIn, Concert, Payment, Queue, Waitlist)
         |
         v
[ SQL Server - ConcertTicketingDB ]  <- Thick DB: 27 bảng, 26 SP, 26 trigger, 6 view, 3 function
```

### Nguyên tắc 4 actor → 3 luồng UI (chuẩn thế giới)

Nghiên cứu production (Ticketmaster, Eventbrite, SeatGeek, AXS) chỉ ra: **không xây 1 app cho 1 actor**,
mà gộp theo bối cảnh sử dụng. Hệ thống này có **4 actor nhưng 3 luồng**:

| Luồng UI | Actor | Frontend hiện tại | Ghi chú |
| :--- | :--- | :--- | :--- |
| **Customer (storefront)** | Customer | Home, Concert, Checkout | Có sẵn |
| **Backoffice** | Admin + Organizer | — (cần xây mới) | Admin toàn quyền; Organizer thấy concert của mình |
| **Staff** | Check-in Staff | StaffCheckIn | Có sẵn |

> Admin và Organizer dùng **chung luồng backoffice** vì cùng thao tác trên Concert/Venue/Seat/Promotion;
> được phân biệt ở tầng **API/DB** (Admin: toàn hệ thống; Organizer: chỉ concert sở hữu — BR37/FR49),
> không cần tách thành 2 app riêng (khớp Eventbrite Dashboard: 1 organizer dashboard, admin ẩn trong hệ thống).

---

## 2. Tech Stack

| Mục | Công nghệ | Ghi chú |
| :--- | :--- | :--- |
| **Framework** | React 19 + Vite 8 | Đang dùng |
| **Router** | react-router-dom 7 | Đang dùng (`BrowserRouter`) |
| **State** | React Context (`AuthContext`) | Không dùng Redux — state toàn cục chỉ auth |
| **HTTP** | axios (instance + interceptor) | Đang dùng — Bearer + refresh + 401/429 |
| **UI** | CSS thuần (không UI lib) | Giữ nguyên phong cách hiện tại |
| **Form** | Controlled components | Không dùng React Hook Form (form ít) |
| **Date** | `Intl.DateTimeFormat` | Không cần date-fns |
| **Testing** | Vitest + React Testing Library | Phase 5 |
| **Build** | `vite build` → static | Phase 5: proxy `/api` → backend |

> [!NOTE]
> Stack tối ưu cho phạm vi đồ án: không thêm TanStack Query/Zustand cho đến khi thực sự cần (Phase 5). Hiện tại Context + axios đủ cho 4 actor.
---

## 3. Cấu Trúc Thư Mục Mục Tiêu

```
frontend/
+-- src/
    +-- api/
    |   +-- axios.js              (đã có: Bearer + refresh + 401/429)
    |   +-- auth.js               (đã có: set/getAccessToken)
    |   +-- endpoints.js          (MỚI: hằng số URL tập trung)
    +-- auth/
    |   +-- AuthContext.jsx       (MỚI: user, role, login/logout, token decode)
    |   +-- useAuth.js            (MỚI: hook)
    |   +-- jwt.js                (MỚI: decode payload JWT → userId, roles, exp)
    +-- routes/
    |   +-- ProtectedRoute.jsx    (MỚI: yêu cầu đăng nhập)
    |   +-- RoleRoute.jsx         (MỚI: yêu cầu 1 trong các role)
    |   +-- routes.js             (MỚI: khai báo route + layout + role)
    +-- layouts/
    |   +-- CustomerLayout.jsx    (MỚI: navbar shop)
    |   +-- BackofficeLayout.jsx  (MỚI: sidebar admin/org)
    |   +-- StaffLayout.jsx       (MỚI: tối giản, mobile-first)
    +-- pages/
    |   +-- Auth.jsx              (đã có)
    |   +-- Home.jsx              (đã có)
    |   +-- Concert.jsx           (đã có)
    |   +-- Checkout.jsx          (đã có)
    |   +-- Success.jsx           (MỚI: kết quả thanh toán + My Tickets)
    |   +-- MyBookings.jsx        (MỚI: lịch sử + hủy booking)
    |   +-- StaffCheckIn.jsx      (đã có)
    |   +-- backoffice/
    |   |   +-- Concerts.jsx      (MỚI: CRUD concert + status)
    |   |   +-- Venues.jsx        (MỚI: venue/zone/seat)
    |   |   +-- Categories.jsx    (MỚI: ticket category + event seats + giá)
    |   |   +-- Promotions.jsx    (MỚI: promotion + discount code)
    |   |   +-- Users.jsx         (MỚI: role assignment + user status)
    |   |   +-- StaffAssign.jsx   (MỚI: check-in staff assignment)
    |   |   +-- Dashboard.jsx     (MỚI: số liệu tổng quan từ view)
    |   +-- FairAccess.jsx        (MỚI: waitlist + queue trạng thái của tôi)
    +-- components/
    |   +-- DataTable.jsx         (MỚI: bảng + phân trang)
    |   +-- Modal.jsx             (MỚI: form popup)
    |   +-- Toast.jsx             (MỚI: thông báo)
    |   +-- SeatMap.jsx           (MỚI: tách từ Concert.jsx cho tái dùng)
    +-- App.jsx                   (sửa: khai báo routes + AuthProvider)
    +-- main.jsx                  (sửa: bọc AuthProvider)
```

---

## 4. Auth & Role Model (then chốt)

### 4.1 Dữ liệu role lấy từ đâu

Backend `AuthResponse` hiện trả: `AccessToken`, `TokenType`, `ExpiresIn` — **không kèm role riêng**.
Role nằm trong **JWT claims** (mỗi role là 1 claim `ClaimTypes.Role`), kèm `sub`=UserID, `email`, `displayName`.

→ Frontend phải **decode JWT payload** khi nhận token mới:

```js
// src/auth/jwt.js
export function decodeJwt(token) {
  try {
    const base64Url = token.split('.')[1];
    const base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
    const json = decodeURIComponent(
      atob(base64).split('').map(c => '%' + ('00' + c.charCodeAt(0).toString(16)).slice(-2)).join('')
    );
    return JSON.parse(json);        // { sub, email, displayName, role: 'Admin', exp, ... }
  } catch { return null; }
}
```

> [!WARNING]
> JWT role chỉ để **điều hướng UI**, không phải bảo mật. Bảo mật thật ở backend: mỗi API request
> được kiểm tra `[Authorize(Roles = "...")]` + SP check quyền trong DB. Frontend che nút
> ≠ phân quyền (theo OWASP Authorization Cheat Sheet — "validate permissions on every request").
| **Routing** | react-router-dom 7 | `Routes` + `Navigate` |
| **HTTP** | Axios 1.x | Interceptor Bearer token + refresh |
| **State & Auth** | React Context + Hook | `AuthContext`, `RoleRoute` |
| **Query** | TanStack Query (khuyến nghị thêm) | Caching, retry, staleTime cho API GET |
| **UI Kit** | Component tự viết + CSS variables | Đang dùng `var(--...)` / `glass-card` |
| **Form** | Không dùng thư viện lớn | Form ít; React state đủ |
| **Build** | Vite build → static | Deploy sau proxy/reverse-proxy |
| **Lint** | oxlint | Đã cấu hình |
| **Testing** | Vitest + React Testing Library (khuyến nghị) | Unit cho helper/guard |
### 4.2 AuthContext

```jsx
// src/auth/AuthContext.jsx
const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);     // { userId, email, displayName, roles: [] }
  const [ready, setReady] = useState(false);  // tránh redirect vội khi chưa decode

  const applyToken = useCallback((token) => {
    setAccessToken(token);
    const payload = decodeJwt(token);
    setUser(payload ? {
      userId: Number(payload.sub),
      email: payload.email,
      displayName: payload.displayName,
      roles: typeof payload.role === 'string' ? [payload.role] : (payload.role ?? []),
    } : null);
  }, []);

  // Vào app: thử refresh nếu có cookie (login-state recovery)
  useEffect(() => {
    (async () => {
      try {
        const res = await axios.post('/api/auth/refresh', {}, { withCredentials: true });
        applyToken(res.data.accessToken);
      } catch { /* chưa đăng nhập */ }
      setReady(true);
    })();
  }, [applyToken]);

  const logout = async () => {
    try { await api.post('/auth/logout'); } catch {}
    setAccessToken(null); setUser(null);
    window.dispatchEvent(new Event('auth:logout'));
  };

  return <AuthContext.Provider value={{ user, ready, applyToken, logout }}>{children}</AuthContext.Provider>;
}
export const useAuth = () => useContext(AuthContext);
```

### 4.3 Route guards

```jsx
// src/routes/ProtectedRoute.jsx
export function ProtectedRoute({ children }) {
  const { user, ready } = useAuth();
---

## 5. Mapping Endpoint → Frontend (33 endpoints backend)

### 5.1 Auth & Concert & Booking (có sẵn — chỉ chỉnh)

| Endpoint | Trang | Trạng thái |
| :--- | :--- | :--- |
| `POST /auth/login`, `/auth/register`, `/auth/refresh`, `/auth/logout` | Auth.jsx, axios.js | ✅ Đã có |
| `GET /concerts` | Home.jsx | ✅ Đã có |
| `GET /concerts/{id}` | Concert.jsx | ✅ Đã có |
| `GET /concerts/{id}/seats` | Concert.jsx (`SeatMap`) | ✅ Đã có |
| `POST /bookings` | Concert.jsx | ✅ Đã có |
| `GET /bookings/{id}` | Checkout.jsx | ✅ Đã có |
| `POST /bookings/{id}/promotion` | Checkout.jsx | ✅ Đã có |
| `DELETE /bookings/{id}` | **MyBookings.jsx (MỚI)** | ❌ Thiếu |

### 5.2 Payment (mở rộng)

| Endpoint | Trang | Trạng thái |
| :--- | :--- | :--- |
| `POST /bookings/{id}/payment` | Checkout.jsx | ✅ Đã có |
| `POST /payments/confirm` | Checkout.jsx | ✅ Đã có |
| `POST /payments/{id}/refund` | **MyBookings.jsx (MỚI)** | ❌ Thiếu |

### 5.3 Backoffice (Admin + Organizer — toàn bộ mới)

| Endpoint | Trang backoffice | Nút/Thao tác |
| :--- | :--- | :--- |
| `POST /admin/concerts` | Concerts.jsx | Tạo concert (form) |
| `PUT /admin/concerts/{id}` | Concerts.jsx | Sửa concert (modal) |
| `PATCH /admin/concerts/{id}/status` | Concerts.jsx | Dropdown status |
| `POST /admin/venues` | Venues.jsx | Form venue |
| `POST /admin/venues/{vid}/zones` | Venues.jsx | Form zone |
| `POST /admin/zones/{zid}/seats` | Venues.jsx | Form seat (bulk) |
| `POST /admin/concerts/{cid}/categories` | Categories.jsx | Form category |
| `POST /admin/concerts/{cid}/event-seats` | Categories.jsx | Chọn seats + giá |
| `POST /admin/concerts/{cid}/promotions` | Promotions.jsx | Form promotion |
| `POST /admin/promotions/{pid}/discount-codes` | Promotions.jsx | Form code |
| `PATCH /admin/event-seats/{esid}/availability` | Concerts.jsx | Nút Unavailable |
| `POST /admin/roles/assign` | Users.jsx | Select role Grant/Revoke |
| `PATCH /admin/users/{uid}/status` | Users.jsx | Dropdown status |
| `POST /admin/checkin-staff-assignments` | StaffAssign.jsx | Chọn staff + concerts |

### 5.4 Fair Access (mới cho Customer)

| Endpoint | Trang | Thao tác |
| :--- | :--- | :--- |
| `POST /waitlist/concerts/{id}/join` | Concert.jsx / FairAccess.jsx | Nút "Join Waitlist" khi hết ghế |
| `GET /waitlist/concerts/{id}/me` | FairAccess.jsx | Vị trí chờ |
| `POST /queue/concerts/{id}/join` | Concert.jsx | Nút khi FairAccess bật |
| `GET /queue/concerts/{id}/me` | FairAccess.jsx | Vị trí + trạng thái |

---

## 6. Chi Tiết Từng Actor

### 6.1 Customer (storefront)
- **Người dùng chưa đăng nhập**: xem Home + Concert detail + sơ đồ ghế (chỉ đọc).
- **Đã đăng nhập**: chọn ghế → `POST /bookings` → Checkout → áp mã giảm → thanh toán → `Success`.
- **My Bookings** (`/my-bookings`): danh sách booking của mình, trạng thái (Pending/Confirmed/Cancelled/Expired),
  nút **Hủy** (nếu Pending → `DELETE /bookings/{id}`), nút **Hoàn tiền** (nếu Confirmed + policy → refund).
- **Fair Access**: khi ghế hết hoặc concert bật waitlist/queue → nút Join → xem vị trí → poll `/me`.

### 6.2 Admin (backoffice toàn quyền)
- **Dashboard**: số liệu từ `VW_ConcertSalesSummary` (backend `GET /concerts` list + computed summary UI).
- **Concerts**: bảng concert (tên, status, giá, limit), nút tạo/sửa, dropdown đổi status
  (Draft→Published→OnSale→SaleClosed→Completed/Cancelled), toggle `Unavailable` từng EventSeat.
- **Venues/Zone/Seats**: 2 lớp form, tạo hàng loạt.
- **Categories & EventSeats**: category + chọn ghế + giá bán.
- **Promotions & Discount codes**: tạo promotion, sinh code, xem danh sách.
- **Users & Roles**: gán role (Grant/Revoke), đổi status (Active/Locked/Disabled).
- **Staff assignment**: chọn nhân viên Check-in + danh sách concert.

### 6.3 Organizer (backoffice giới hạn)
- Cùng giao diện `Concerts`/`Promotions` nhưng **dữ liệu chỉ concert mình sở hữu** (do API/SP lọc,
  frontend không lọc). Không thấy tab Users/Venues global.

### 6.4 Check-in Staff
- `StaffCheckIn` hiện tại: nhập ConcertID + TicketCode → `POST /checkin` → show `validationResult`.
- **Nâng cấp (khuyến nghị)**: danh sách concert được phân công (qua `CheckinStaffAssignment`), chọn
  concert thay vì nhập ID; không có quyền gì khác.

---

## 7. Xử Lý Lỗi / Loading / Bảo Mật

| Tình huống | Xử lý |
| :--- | :--- |
| 401 | axios interceptor đã có → refresh 1 lần; fail thì logout → `/login` |
| 403 | RoleRoute bắt trước; nếu API vẫn trả 403 (thừa quyền) → toast + điều hướng `/403` |
| 409 | Concert chưa OnSale, ghế đã giữ, booking không Pending → toast lấy `detail` |
| 422 | Validator trả ProblemDetails → hiện `detail` |
| 429 | interceptor đã dispatch `api:ratelimit` → toast "quá nhiều yêu cầu" |
| Network | Loading state + nút retry |
| Hết hạn hold | Checkout countdown → hết giờ → disable nút + nút "Chọn lại ghế" |

**Nguyên tắc bảo mật (OWASP):**
1. Role ở UI chỉ để điều hướng — backend/DB là enforcement thật.
2. Không nhúng token vào localStorage (đang dùng in-memory + HttpOnly cookie — giữ vậy).
3. XSS: không `dangerouslySetInnerHTML` với dữ liệu người dùng.

---

## 8. Lộ Trình Triển Khai (Phases)

### Phase 1 — Nền tảng auth & routing (nửa ngày)
- [ ] `jwt.js`, `AuthContext.jsx`, `useAuth.js`
- [ ] `ProtectedRoute`, `RoleRoute`, routes map
- [ ] Sửa `App.jsx`, `main.jsx` bọc `AuthProvider`
- [ ] Login/Register decode role → Navbar đổi theo role

### Phase 2 — Hoàn thiện luồng Customer (1-2 ngày)
- [ ] `MyBookings.jsx` (list + cancel)
- [ ] Refund UI trong MyBookings (khi policy cho phép)
- [ ] `Success.jsx` sau thanh toán
- [ ] `SeatMap.jsx` tách component từ Concert.jsx

### Phase 3 — Backoffice Admin+Organizer (2-3 ngày)
- [ ] `BackofficeLayout` (sidebar)
- [ ] `Concerts.jsx` (+ status, + event-seat availability)
- [ ] `Venues.jsx` (venue/zone/seat)
- [ ] `Categories.jsx` (category + event seats + giá)
- [ ] `Promotions.jsx` (promotion + code)
- [ ] `Users.jsx` (role assign + status)
- [ ] `StaffAssign.jsx`
- [ ] `Dashboard.jsx`

### Phase 4 — Fair Access + tinh chỉnh (1 ngày)
- [ ] Waitlist join + `/me` + "dùng cơ hội" (booking với waitlistEntryId)
- [ ] Queue join + `/me` + admitted → booking
- [ ] `FairAccess.jsx`

### Phase 5 — Nâng cấp chất lượng (khuyến nghị)
- [ ] TanStack Query cho GET cache
- [ ] Vitest: `jwt.test.js`, `RoleRoute.test.jsx`
- [ ] `endpoints.js` tập trung URL (1 nguồn sửa khi đổi backend)
- [ ] Deploy build: `npm run build` → static + proxy `/api` → backend
> [!NOTE]
> - Sau khi join waitlist → backend trả `WaitlistEntryID`; khi được grant (DB cấp OfferedEventSeatID),
>   Customer bấm "Dùng cơ hội" → `POST /bookings` với `{ concertId, seatIds:[], waitlistEntryId }`.
> - Queue: khi `EntryStatus=Admitted` → redirect vào trang booking bình thường.
  if (!ready) return <FullPageLoader />;
  return user ? children : <Navigate to="/login" replace />;
}

// src/routes/RoleRoute.jsx
export function RoleRoute({ roles, children }) {
  const { user } = useAuth();
  if (!user || !roles.some(r => user.roles.includes(r))) {
    return <Navigate to="/403" replace />;
  }
  return children;
}
```

Vai trò → route map:

| Role (DB: `RoleName`) | Route mở | Layout |
| :--- | :--- | :--- |
| Customer | `/`, `/concert/:id`, `/checkout/:bookingId`, `/success`, `/my-bookings`, `/fair-access` | CustomerLayout |
| Admin | `/admin/*` (toàn bộ backoffice) | BackofficeLayout |
| Organizer | `/admin/concerts`, `/admin/promotions` (phạm vi sở hữu qua API/DB) | BackofficeLayout |
| Check-in Staff | `/checkin` | StaffLayout |

> [!NOTE]
> Không dùng Redux: hệ thống 4 actor, state toàn cục chỉ có auth — Context đủ, tránh over-engineer.