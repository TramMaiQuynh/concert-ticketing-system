# Kế Hoạch Xây Dựng Backend — Concert Ticketing System
*Production-grade Thin Backend cho Thick Database (SQL Server)*
*Version 3.0 — Authoritative. Mọi quyết định kiến trúc phản ánh đúng 100% codebase.*

> [!IMPORTANT]
> Nguyên tắc cốt lõi: **Backend không tái triển khai bất kỳ Business Rule nào đã có trong Database.** Mọi thao tác ghi dữ liệu nghiệp vụ đều đi qua Stored Procedures. Backend chỉ thực hiện: (1) Xác thực JWT, (2) Validate DTO đầu vào, (3) Gọi SP/View qua Dapper, (4) Map kết quả/lỗi ra HTTP Response.

---

## 1. Kiến Trúc Tổng Thể

```
[ Frontend / Mobile App ]
         | (HTTPS)
         v
[ Nginx / Reverse Proxy ]  <- TLS Termination, ForwardedHeaders
         |
         v
[ ASP.NET Core 9 Web API ]  <- Thin Backend Layer
  Controllers, Middleware (ErrorHandling + Serilog), Services (AuthService), Repositories (Dapper)
         |                              |
         v                              v
[ SQL Server - ConcertTicketingDB ]  [ Redis - SeatMapCache TTL 15s + SemaphoreSlim Mutex ]
  27 Tables, 10 SPs, 14+ Triggers
  6 Views, HangFire schema
         |
         v
[ IHostedService: HoldReleaseWorker ]
  (PeriodicTimer 1 phút: sp_ReleaseExpiredHolds -> sp_AllocateWaitlist per Concert)
         |
         v
[ Hangfire Server ]  <- Dashboard /hangfire (Đã cấu hình nhưng chưa có Job cụ thể ở phase này)
```

### Phân tầng Backend

| Layer | Vai trò | Thư mục |
| :--- | :--- | :--- |
| **Presentation** | HTTP routing, JSON Serialize/Deserialize | `API/Controllers/` |
| **Application** | Auth orchestration, DTOs, Validators, Interfaces | `Application/` |
| **Data Access** | Dapper → Stored Procedures / Views | `Infrastructure/Repositories/` |
| **Infrastructure** | Cache (Redis), Background Jobs | `Infrastructure/Cache/`, `Infrastructure/BackgroundJobs/` |
| **Domain** | C# Model classes ánh xạ từ DB Tables | `Domain/Models/` |

---

## 2. Tech Stack

| Mục | Công nghệ | Ghi chú |
| :--- | :--- | :--- |
| **Framework** | ASP.NET Core 9 (Web API) | Native với SQL Server |
| **Data Access** | Dapper 2.x | Micro-ORM, gọi SP thô không can thiệp Schema |
| **Validation** | FluentValidation + FluentValidation.AspNetCore | Auto-validation qua `AddFluentValidationAutoValidation()` |
| **Auth** | JWT Bearer (Microsoft.AspNetCore.Authentication.JwtBearer) | Stateless, RFC 7519, HMAC-SHA256 |
| **Password Hashing** | BCrypt.Net-Next (cost=12) | Self-salting — không cần cột PasswordSalt riêng |
| **Refresh Token** | SHA-256 (System.Security.Cryptography) | Raw token 64 bytes random; DB chỉ lưu SHA-256 hex hash |
| **Rate Limiting** | Microsoft.AspNetCore.RateLimiting (built-in ASP.NET Core 9) | SlidingWindow + FixedWindow |
| **Cache** | Redis (StackExchange.Redis) + SemaphoreSlim Mutex | TTL + Single-Flight chống Cache Stampede |
| **Background Job (critical)** | Hangfire (Hangfire.SqlServer) | Email vé — retry + persistence + dashboard |
| **Background Job (periodic)** | IHostedService + PeriodicTimer | sp_ReleaseExpiredHolds + sp_AllocateWaitlist mỗi 1 phút |
| **Logging** | Serilog (ReadFrom.Configuration + ReadFrom.Services) | Structured logging |
| **API Docs** | Scalar (ScalarTheme.DeepSpace) + ASP.NET Core OpenAPI | Chỉ Development |
| **DB Client** | Microsoft.Data.SqlClient | |
| **Testing** | xUnit + Testcontainers | Unit test + Integration test với DB thật |

> [!NOTE]
> **Tại sao dùng cả Hangfire lẫn IHostedService?**
> - `IHostedService (HoldReleaseWorker)`: Job định kỳ đơn giản, idempotent. App restart thì SP chạy lại ở chu kỳ tiếp theo là OK. Không cần persistence hay retry.
> - `Hangfire`: Sẵn sàng cho các job nghiệp vụ (vd: Email) cần retry từ DB. Hiện tại chỉ setup Dashboard và Schema.

> [!IMPORTANT]
> **Hangfire dùng `PrepareSchemaIfNecessary = false`.** Schema HangFire phải được tạo trước qua `database/Scripts/HangfireSchema.sql` trong `deploy.ps1`. Backend không tự tạo schema.

---

## 3. Cấu Trúc Thư Mục

```
backend/
+-- src/
|   +-- ConcertTicketing.API/
|   |   +-- Controllers/
|   |   |   +-- AuthController.cs        # POST login/register/refresh/logout
|   |   |   +-- BookingController.cs     # CRUD Booking + ApplyPromotion
|   |   |   +-- CheckInController.cs     # POST checkin (Role: Staff)
|   |   |   +-- ConcertController.cs     # GET concerts + seats (public)
|   |   |   +-- PaymentController.cs     # Initiate + Confirm (webhook) + Refund
|   |   +-- Middleware/
|   |   |   +-- ErrorHandlingMiddleware.cs   # SqlException -> RFC 7807 Problem Details
|   |   +-- HangfireAdminAuthFilter.cs   # Bảo vệ /hangfire dashboard
|   |   +-- Program.cs                   # DI, Middleware pipeline, Config
|   |
|   +-- ConcertTicketing.Application/
|   |   +-- DTOs/Dtos.cs                 # Tất cả Request/Response records
|   |   +-- Interfaces/IRepositories.cs  # Interface contracts cho 5 Repositories
|   |   +-- Services/AuthService.cs      # BCrypt.Verify, JWT generate, Refresh Token
|   |   +-- Validators/Validators.cs     # FluentValidation cho mọi Request DTO
|   |
|   +-- ConcertTicketing.Infrastructure/
|   |   +-- BackgroundJobs/
|   |   |   +-- HoldReleaseWorker.cs     # IHostedService: sp_ReleaseExpiredHolds + sp_AllocateWaitlist
|   |   +-- Cache/SeatMapCache.cs        # TTL 15s + SemaphoreSlim Mutex (single-process)
|   |   +-- Repositories/
|   |       +-- BookingRepository.cs     # sp_CreateBooking, sp_CancelBooking, sp_ApplyPromotion
|   |       +-- CheckInRepository.cs     # sp_CheckInTicket (OUTPUT parameters)
|   |       +-- ConcertRepository.cs     # SELECT Concert/EventSeat/Views
|   |       +-- PaymentRepository.cs     # sp_InitiatePayment, sp_ConfirmPayment, sp_ProcessRefund
|   |       +-- UserRepository.cs        # sp_RegisterUser + Auth queries + RefreshToken CRUD
|   |
|   +-- ConcertTicketing.Domain/Models/
|       +-- Booking.cs, Concert.cs, EventSeat.cs, UserAccount.cs
|
+-- tests/
    +-- ConcertTicketing.UnitTests/
    +-- ConcertTicketing.IntegrationTests/
```

---

## 4. Data Transfer Objects (DTOs)

Tất cả DTOs là C# `record` (immutable). Định nghĩa tập trung trong `Application/DTOs/Dtos.cs`.

### 4.1 Auth DTOs

```csharp
record LoginRequest(string Username, string Password);

record RegisterRequest(string Username, string Email, string Password, string DisplayName);

// RefreshToken KHÔNG trả trong body — được set qua HttpOnly Cookie
record AuthResponse(string AccessToken, string TokenType, int ExpiresIn);
// TokenType luôn là "Bearer", ExpiresIn = AccessTokenExpiryMinutes * 60
```

### 4.2 Concert DTOs

```csharp
record ConcertListItem(
    int ConcertID, string ConcertName, string ArtistName,
    string VenueName, string Address, DateTime StartDatetime,
    string ConcertStatus, bool SalesPaused, DateTime? SaleStartDatetime);

record ConcertDetail(
    int ConcertID, string ConcertName, string ArtistName,
    string VenueName, string Address, DateTime StartDatetime,
    string ConcertStatus, bool SalesPaused,
    DateTime? SaleStartDatetime, DateTime? SaleEndDatetime, int? PurchaseLimit);

record SeatDto(
    int SeatID, string SeatNumber, string? SectionName,
    string? Row, string CategoryName, string InventoryStatus, decimal Price);
```

### 4.3 Booking DTOs

```csharp
record CreateBookingRequest(int ConcertId, List<int> SeatIds, int? WaitlistEntryId = null);

record CreateBookingResponse(
    int BookingId, string BookingReference,
    DateTime HoldExpiryDatetime, decimal SubtotalAmount, decimal FinalAmount, string Status);

record BookingDetail(
    int BookingID, int ConcertID, string ConcertName,
    string BookingStatus, DateTime CreatedTimestamp, DateTime? HoldExpiryDatetime,
    decimal SubtotalAmount, decimal DiscountAmount, decimal FinalAmount,
    string BookingReference, List<BookingAllocationDto> Seats);

record BookingAllocationDto(
    int SeatID, string SeatNumber, string? SectionName,
    string CategoryName, decimal PriceAtBooking);

record ApplyPromotionRequest(string DiscountCode);
```

### 4.4 Payment DTOs

```csharp
// Empty body — BookingID lấy từ URL, CustomerID lấy từ JWT
record InitiatePaymentRequest();

record InitiatePaymentResponse(
    int PaymentId, string PaymentUrl, string PaymentReference, decimal Amount);

record RefundRequest(decimal RefundAmount, string Reason);
```

### 4.5 CheckIn DTOs

```csharp
record CheckInRequest(string TicketCode, int ConcertId);

record CheckInResponse(
    string ValidationResult,  // SUCCESS / ALREADY_USED / INVALID / WRONG_CONCERT / ...
    string ValidationInfo,
    DateTime? CheckInTime);
```

### 4.6 Phân trang

```csharp
record PagedResult<T>(IEnumerable<T> Items, int TotalCount, int Page, int PageSize)
{
    public int TotalPages => (int)Math.Ceiling((double)TotalCount / PageSize);
}
```

---

## 5. FluentValidation Rules

Tất cả Validators trong `Application/Validators/Validators.cs`. Auto-validation bật qua `AddFluentValidationAutoValidation()`.

| Validator | Rules |
| :--- | :--- |
| `LoginValidator` | Username: NotEmpty max 100; Password: NotEmpty min 6 |
| `RegisterValidator` | Username: 3–50 ký tự regex `^[a-zA-Z0-9_]+$`; Email: định dạng hợp lệ; Password: min 8 có chữ hoa + chữ số; DisplayName: NotEmpty max 200 |
| `CreateBookingValidator` | ConcertId > 0; SeatIds: NotEmpty tối đa 10 ghế không trùng lặp mỗi ID > 0 |
| `ApplyPromotionValidator` | DiscountCode: NotEmpty max 50 |
| `CheckInValidator` | TicketCode: NotEmpty max 100; ConcertId > 0 |

---

## 6. Repository Interfaces

Định nghĩa trong `Application/Interfaces/IRepositories.cs`. Implementation trong `Infrastructure/Repositories/`.

```csharp
interface IUserRepository {
    Task<UserAccount?> GetByUsernameAsync(string username);
    Task<UserAccount?> GetByIdAsync(int userId);
    Task<IEnumerable<string>> GetRolesAsync(int userId);
    Task<int> CreateAsync(UserAccount user, string passwordHash);  // -> EXEC sp_RegisterUser
    Task<string> CreateRefreshTokenAsync(int userId, DateTime expiryUtc);
    Task<(int UserId, bool IsValid)> ValidateRefreshTokenAsync(string rawToken);
    Task RevokeRefreshTokenAsync(string rawToken);
}

interface IBookingRepository {
    Task<CreateBookingResponse> CreateAsync(int customerUserId, CreateBookingRequest request); // -> sp_CreateBooking
    Task<BookingDetail?> GetByIdAsync(int bookingId, int customerUserId);
    Task CancelAsync(int bookingId, int customerUserId);                                       // -> sp_CancelBooking
    Task ApplyPromotionAsync(int bookingId, int customerUserId, string discountCode);          // -> sp_ApplyPromotion
}

interface IConcertRepository {
    Task<IEnumerable<ConcertListItem>> GetListAsync(int page, int pageSize, string? status);
    Task<ConcertDetail?> GetByIdAsync(int concertId);
    Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId);
}

interface ICheckInRepository {
    Task<CheckInResponse> CheckInAsync(int staffUserId, CheckInRequest request); // -> sp_CheckInTicket
}

interface IPaymentRepository {
    Task<InitiatePaymentResponse> InitiateAsync(int bookingId, int customerUserId);              // -> sp_InitiatePayment
    Task ConfirmAsync(int bookingId, int paymentId, string? providerReference);                  // -> sp_ConfirmPayment
    Task<int> ProcessRefundAsync(int paymentId, decimal amount, string reason, int actorUserId); // -> sp_ProcessRefund
}
```

---

## 7. Thiết Kế API Endpoints

### 7.1 Authentication (`/api/auth`)

> Backend xử lý toàn bộ logic Auth. DB chỉ lưu `PasswordHash` (BCrypt, self-salting) và `SHA-256(RefreshToken)`.

```
POST /api/auth/register  -> sp_RegisterUser (qua UserRepository.CreateAsync)
POST /api/auth/login     -> SELECT UserAccount + BCrypt.Verify + phát JWT Pair
POST /api/auth/refresh   -> ValidateRefreshToken (SHA-256) + Rotation + phát JWT Pair mới
POST /api/auth/logout    -> RevokeRefreshToken (SET IsRevoked=1, không DELETE)
```

**Luồng Register:**
1. FluentValidation: Username regex `^[a-zA-Z0-9_]+$`, Password min 8 + uppercase + digit.
2. `AuthService.RegisterAsync()` → `BCrypt.HashPassword(password, cost=12)`.
3. `UserRepository.CreateAsync()` → `EXEC sp_RegisterUser @Username, @Email, @PasswordHash, @DisplayName, @NewUserID OUTPUT`.
4. SP tự tạo `UserAccount` + gán Role `Customer` + ghi `AuditRecord` trong 1 transaction.
5. Phát JWT Access Token + Refresh Token qua HttpOnly Cookie.

**Luồng Login:**
1. `UserRepository.GetByUsernameAsync()` → `SELECT ... FROM UserAccount WHERE Username=@Username AND AccountStatus='Active'`.
2. `BCrypt.Verify(password, storedHash)` → nếu sai throw `UnauthorizedAccessException`.
3. `UserRepository.GetRolesAsync()` → `SELECT r.RoleName FROM UserRoleAssignment ... WHERE AssignmentStatus='Active' AND RoleStatus='Active'`.
4. `GenerateAccessToken()` → JWT chứa `{ sub: UserID, jti: Guid, email, displayName, roles[] }`, HMAC-SHA256.
5. `CreateRefreshTokenAsync()` → raw token 64 bytes (`RandomNumberGenerator.GetBytes(64)`) → SHA-256 hex → INSERT `RefreshToken` table.
6. Trả về `AuthResponse(AccessToken, "Bearer", ExpiresIn)` + set `refreshToken` HttpOnly Cookie.

**Refresh Token Cookie:**
```csharp
Response.Cookies.Append("refreshToken", rawToken, new CookieOptions {
    HttpOnly = true,
    Secure   = Request.IsHttps,
    SameSite = SameSiteMode.Strict,
    Expires  = DateTimeOffset.UtcNow.AddDays(RefreshTokenExpiryDays),
    Path     = "/api/auth"  // Cookie chỉ gửi đến /api/auth/* — giới hạn phạm vi tối đa
});
```

**Luồng Refresh (Refresh Token Rotation):**
1. Đọc raw token từ HttpOnly Cookie.
2. SHA-256 hex → query `RefreshToken WHERE TokenHash=? AND ExpiryDatetime > SYSUTCDATETIME() AND IsRevoked=0`.
3. `RevokeRefreshTokenAsync()` → `SET IsRevoked=1` (không DELETE, giữ audit trail).
4. Phát JWT Pair mới (Access Token + Refresh Token mới).

---

### 7.2 Concerts (`/api/concerts`) — Public, không cần Auth

```
GET /api/concerts              -> SELECT Concert + Artist + Venue (Filter, Pagination)
GET /api/concerts/{id}         -> Chi tiết Concert
GET /api/concerts/{id}/seats   -> Danh sách EventSeat (qua SeatMapCache)
```

**Pagination mặc định:** `page=1`, `pageSize=20` (max 100).

**Cache Strategy — `GET /concerts/{id}/seats` (SeatMapCache):**

```csharp
// SeatMapCache.cs — TTL 15s + SemaphoreSlim(1,1) Mutex
public async Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId, CancellationToken ct)
{
    var cacheKey = $"concert:seats:{concertId}";

    // Fast path: cache hit
    var cached = await _redis.StringGetAsync(cacheKey);
    if (cached.HasValue) return Deserialize(cached);

    // Slow path: chỉ 1 luồng được vào DB, các luồng khác chờ (không bắn DB cùng lúc)
    await _lock.WaitAsync(ct);
    try
    {
        // Double-check sau khi vào lock
        cached = await _redis.StringGetAsync(cacheKey);
        if (cached.HasValue) return Deserialize(cached);

        var seats = (await _concertRepository.GetSeatsAsync(concertId)).ToList();
        await _redis.StringSetAsync(cacheKey, Serialize(seats), TimeSpan.FromSeconds(_ttlSeconds));
        return seats;
    }
    finally { _lock.Release(); }
}
```

> [!IMPORTANT]
> TTL có thể cấu hình qua `Redis:SeatMapTtlSeconds` trong `appsettings.json` (default 15).
> `SemaphoreSlim` chỉ hoạt động trong 1 process. Nếu scale lên nhiều instances, phải chuyển sang **Redis Distributed Lock** (`SET NX PX`).

> [!NOTE]
> **Không dùng explicit cache invalidation.** Cache tự hết hạn sau TTL. Chấp nhận dữ liệu trễ 15s — trade-off tránh Cache Stampede khi concert có hàng chục nghìn người xem đồng thời.

---

### 7.3 Bookings (`/api/bookings`) — `[Authorize]`

```
POST   /api/bookings                  -> EXEC sp_CreateBooking    [Role: Customer] [RateLimit: booking]
GET    /api/bookings/{id}             -> SELECT Booking + Allocations (CustomerID filter từ JWT)
POST   /api/bookings/{id}/promotion   -> EXEC sp_ApplyPromotion   [Role: Customer]
DELETE /api/bookings/{id}             -> EXEC sp_CancelBooking    [Role: Customer]
```

**Luồng `POST /api/bookings`:**
1. JWT Middleware → Lấy `CustomerUserID` từ `ClaimTypes.NameIdentifier`. **KHÔNG BAO GIỜ** lấy từ Request Body.
2. FluentValidation tự động: `ConcertId > 0`, `SeatIds` hợp lệ.
3. Rate Limit `[EnableRateLimiting("booking")]`: 2 req/10s per UserID — chống double-click.
4. `BookingRepository.CreateAsync(userId, request)` → `EXEC sp_CreateBooking @CustomerUserID, @ConcertID, @SeatList='101,102', @WaitlistEntryID, @NewBookingID OUTPUT`.
5. Trả về `201 Created` với `CreateBookingResponse`.

**Luồng `DELETE /api/bookings/{id}`:**
1. `BookingRepository.CancelAsync(id, userId)` → `EXEC sp_CancelBooking @BookingID, @CustomerUserID`.
2. SP chỉ cancel Booking ở trạng thái `Pending`. Confirmed Booking có luồng xử lý riêng biệt.
3. Trả về `204 No Content`.

---

### 7.4 Payments — `[Authorize]`

```
POST /api/bookings/{bookingId}/payment  -> EXEC sp_InitiatePayment  [Role: Customer]
POST /api/payments/confirm              -> EXEC sp_ConfirmPayment    [AllowAnonymous - Webhook]
POST /api/payments/{paymentId}/refund   -> EXEC sp_ProcessRefund     [Role: Admin, Organizer]
```

**Luồng Thanh Toán Hoàn Chỉnh:**
```
[Frontend]           [Backend]              [VNPay]           [DB]
    |--POST /payment->|                       |                |
    |                 |--EXEC sp_InitiatePayment-------------->|
    |                 |  SP tự sinh PaymentReference = 'PAY-'+NEWID()
    |                 |  SP INSERT Payment Status='Pending'    |
    |                 |<-- PaymentID, Ref, Amount -------------|
    |                 |-- VNPay.CreatePaymentUrl() ----------->|
    |<-- paymentUrl --|                       |                |
    |-- Redirect -------------------------------->             |
    |                 |<--- POST /confirm ----|                |
    |                 |  ?bookingId=&paymentId=&vnp_TransactionNo=
    |                 |-- EXEC sp_ConfirmPayment ------------->|
    |                 |<-- OK ---------------------------------|
    |                 |-- 200 OK ----------->|                |
```

**Webhook `POST /api/payments/confirm`:**
- `[AllowAnonymous]` — VNPay không gửi JWT.
- Nhận parameters từ query string: `bookingId`, `paymentId`, `vnp_TransactionNo`.
- Gọi `PaymentRepository.ConfirmAsync(bookingId, paymentId, vnp_TransactionNo)`.
- Luôn trả `200 OK` để VNPay không retry vô hạn.

> [!IMPORTANT]
> **`sp_InitiatePayment` tự sinh `PaymentReference`** bên trong SP dùng `NEWID()`. Backend không tự sinh và truyền vào — `api_service` bị `DENY INSERT` trực tiếp trên bảng `Payment`.

---

### 7.5 Check-In (`/api/checkin`) — `[Authorize(Roles = "Staff")]`

```
POST /api/checkin   -> EXEC sp_CheckInTicket [Role: Staff] [RateLimit: checkin]
```

**Luồng Check-In:**
```csharp
// CheckInRepository.cs
var p = new DynamicParameters();
p.Add("@TicketCode",        request.TicketCode,  DbType.String);
p.Add("@ConcertID",         request.ConcertId,   DbType.Int32);
p.Add("@CheckInStaffUserID", staffUserId,         DbType.Int32);
p.Add("@ValidationResult",  dbType: DbType.String, size: 32,  direction: ParameterDirection.Output);
p.Add("@ValidationInfo",    dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

await conn.ExecuteAsync("sp_CheckInTicket", p, commandType: CommandType.StoredProcedure);

return new CheckInResponse(
    p.Get<string>("@ValidationResult"),
    p.Get<string>("@ValidationInfo"),
    CheckInTime: DateTime.UtcNow);
```

- SP tự xử lý toàn bộ logic và Audit (kể cả khi INVALID/ALREADY_USED).
- Luôn trả `200 OK` — Frontend dùng `ValidationResult` để hiển thị màu xanh/đỏ.

> [!NOTE]
> Role trong JWT là `"Staff"` (tên claim), ánh xạ từ tên role `"Check-in Staff"` trong DB. `AuthService.GenerateAccessToken()` phải map đúng tên role từ DB sang claim.

---

## 8. Background Jobs

### 8.1 HoldReleaseWorker (IHostedService — PeriodicTimer)

```csharp
// HoldReleaseWorker.cs
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1));
    while (await timer.WaitForNextTickAsync(stoppingToken))
    {
        try { await ReleaseAndAllocateAsync(stoppingToken); }
        catch (OperationCanceledException) { break; }      // App shutdown bình thường
        catch (Exception ex) { _logger.LogError(ex, ...); } // Tiếp tục, không crash worker
    }
}

private async Task ReleaseAndAllocateAsync(CancellationToken ct)
{
    using var conn = new SqlConnection(_connectionString);
    await conn.OpenAsync(ct);

    // Bước 1: Nhả ghế hết hạn → Available
    await conn.ExecuteAsync(
        "sp_ReleaseExpiredHolds", commandType: CommandType.StoredProcedure, cancellationToken: ct);

    // Bước 2: Lấy danh sách Concert đang OnSale
    var concertIds = await conn.QueryAsync<int>(
        "SELECT ConcertID FROM Concert WHERE ConcertStatus = 'OnSale' AND SalesPaused = 0",
        cancellationToken: ct);

    // Bước 3: Gọi sp_AllocateWaitlist(@ConcertID) cho từng Concert
    foreach (var concertId in concertIds)
    {
        await conn.ExecuteAsync("sp_AllocateWaitlist",
            new { ConcertID = concertId },
            commandType: CommandType.StoredProcedure, cancellationToken: ct);
    }
}
```

> [!IMPORTANT]
> `sp_AllocateWaitlist` **bắt buộc nhận `@ConcertID`** làm tham số. Worker phải truy vấn danh sách Concert `OnSale` và gọi SP cho từng Concert riêng lẻ — không thể gọi 1 lần cho tất cả.

### 8.2 Hangfire Server

- Hangfire đã được tích hợp bằng SQL Server storage (schema `HangFire`), `PrepareSchemaIfNecessary = false`.
- Dashboard hoạt động tại `/hangfire` — bảo vệ bởi `HangfireAdminAuthFilter` (chỉ role Admin).
- Hiện tại chưa có job (như SendTicketEmailJob) được implement trong source code API hiện hành.

---

## 9. Bảo Mật

### 9.1 JWT Claims Structure

```json
{
  "sub":         "157",
  "jti":         "550e8400-e29b-41d4-a716-446655440000",
  "email":       "user@example.com",
  "displayName": "Nguyễn Văn A",
  "roles":       ["Customer"],
  "iss":         "ConcertTicketingAPI",
  "aud":         "ConcertTicketingClient",
  "exp":         1725000000
}
```

- `sub` = `UserID` (int, dạng string theo RFC 7519). Controller đọc bằng `User.FindFirstValue(ClaimTypes.NameIdentifier)`.
- `jti` = `Guid.NewGuid()` — unique per token.

### 9.2 Authorization — Role-Based

| Endpoint | Roles được phép |
| :--- | :--- |
| `POST /api/auth/*` | `[AllowAnonymous]` |
| `GET /api/concerts/*` | `[AllowAnonymous]` |
| `POST /api/bookings` | `Customer` |
| `GET /api/bookings/{id}` | `[Authorize]` (bất kỳ user đã đăng nhập) |
| `POST /api/bookings/{id}/promotion` | `Customer` |
| `DELETE /api/bookings/{id}` | `Customer` |
| `POST /api/bookings/{bookingId}/payment` | `Customer` |
| `POST /api/payments/confirm` | `[AllowAnonymous]` (Webhook) |
| `POST /api/payments/{id}/refund` | `Admin`, `Organizer` |
| `POST /api/checkin` | `Staff` |
| `GET /hangfire` | Admin (HangfireAdminAuthFilter) |

### 9.3 Rate Limiting (Built-in ASP.NET Core 9)

```csharp
builder.Services.AddRateLimiter(options => {
    // booking: chống double-click — per UserID (Sliding Window)
    options.AddSlidingWindowLimiter("booking", opt => {
        opt.Window            = TimeSpan.FromSeconds(10);
        opt.PermitLimit       = 2;
        opt.SegmentsPerWindow = 2;
    });
    // auth: chống Brute Force — per IP (Fixed Window)
    options.AddFixedWindowLimiter("auth", opt => {
        opt.Window      = TimeSpan.FromMinutes(1);
        opt.PermitLimit = 5;
    });
    // checkin: chống quét mã vé — per Staff UserID (Fixed Window)
    options.AddFixedWindowLimiter("checkin", opt => {
        opt.Window      = TimeSpan.FromSeconds(1);
        opt.PermitLimit = 10;
    });
    options.OnRejected = async (ctx, _) => {
        ctx.HttpContext.Response.StatusCode = 429;
        await ctx.HttpContext.Response.WriteAsJsonAsync(
            new { error = "Quá nhiều yêu cầu. Vui lòng thử lại sau." });
    };
});
```

> [!IMPORTANT]
> **Rate Limiter phải đặt SAU `UseAuthentication()` và `UseAuthorization()`** trong pipeline. Nếu đặt trước, `UserID`-based limiter sẽ không có Claims và fall back sang IP-based.

### 9.4 SQL Injection Prevention — Dapper DynamicParameters

```csharp
// Ví dụ: BookingRepository.CreateAsync()
var p = new DynamicParameters();
p.Add("@CustomerUserID", customerUserId,                     DbType.Int32);
p.Add("@ConcertID",      request.ConcertId,                  DbType.Int32);
p.Add("@SeatList",       string.Join(",", request.SeatIds),  DbType.String, size: -1);
p.Add("@WaitlistEntryID", request.WaitlistEntryId,           DbType.Int32);
p.Add("@NewBookingID",   dbType: DbType.Int32, direction: ParameterDirection.Output);

await conn.ExecuteAsync("sp_CreateBooking", p, commandType: CommandType.StoredProcedure);
var bookingId = p.Get<int>("@NewBookingID");
```

Toàn bộ queries dùng Parameterized Query. Không có string concatenation SQL.

### 9.5 Phân Quyền Database (Principle of Least Privilege)

`api_service` được cấu hình trong `database/Security/GrantPermissions.sql`:

```sql
-- GRANT: Thực thi toàn bộ SPs + SELECT toàn bộ schema dbo
GRANT EXECUTE ON SCHEMA::dbo TO api_service;
GRANT SELECT  ON SCHEMA::dbo TO api_service;

-- GRANT ngoại lệ: RefreshToken (C# thao tác trực tiếp cho Auth)
GRANT INSERT, UPDATE ON dbo.RefreshToken TO api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[HangFire] TO api_service;

-- DENY tuyệt đối (Core Business Tables — bắt buộc qua SP)
DENY INSERT, UPDATE, DELETE ON dbo.UserAccount                 TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Booking                     TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.BookingEventSeatAllocation  TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.BookingPromotionApplication TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.EventSeat                   TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Payment                     TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Ticket                      TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Refund                      TO api_service;
DENY SELECT ON dbo.AuditRecord TO api_service;
```

> [!CAUTION]
> Bảng `RefreshToken` là ngoại lệ duy nhất được C# thao tác trực tiếp (không qua SP). Lý do: SHA-256 hash tính trong C# từ raw token chỉ tồn tại trong memory của backend — không thể ủy quyền hợp lý cho SP.

---

## 10. Middleware Pipeline

Thứ tự trong `Program.cs` (quan trọng — sai thứ tự gây lỗi tinh vi):

```
 1. ForwardedHeaders (XForwardedFor, XForwardedProto)  <- Đọc IP thật từ Nginx
 2. UseSerilogRequestLogging()                          <- Log mọi request
 3. UseMiddleware<ErrorHandlingMiddleware>()             <- Bao bọc toàn bộ pipeline
 4. UseHttpsRedirection()                               <- Chỉ non-Development
 5. UseRouting()                                        <- Xác định route
 6. UseAuthentication()                                 <- Giải mã JWT Claims
 7. UseAuthorization()                                  <- Kiểm tra Roles/Policies
 8. UseRateLimiter()                                    <- Sau Auth để dùng UserID
 9. MapControllers()
10. MapHangfireDashboard("/hangfire")                   <- Bảo vệ bởi HangfireAdminAuthFilter
11. MapOpenApi() + MapScalarApiReference()              <- Chỉ Development
12. MapHealthChecks("/healthz")                         <- Kiểm tra DB + Redis
```

---

## 11. Xử Lý Lỗi Chuẩn Hóa (Error Handling)

`ErrorHandlingMiddleware` bắt toàn bộ exception, map sang RFC 7807 Problem Details.

### Mapping SqlException.Number → HTTP Status Code

| SQL Error | Nguồn SP | Ý nghĩa | HTTP |
| :--- | :--- | :--- | :--- |
| 51001 | sp_CreateBooking | Concert không OnSale hoặc SalesPaused | 400 |
| 51002 | sp_CreateBooking | SeatList rỗng | 400 |
| 51003 | sp_CreateBooking | Vượt Purchase Limit | 422 |
| 51004 | sp_CreateBooking | Ghế không còn khả dụng (race condition) | 409 |
| 51005 | sp_CreateBooking | WaitlistEntry không hợp lệ hoặc hết hạn | 400 |
| 52001 | sp_ConfirmPayment | BookingID không tồn tại | 404 |
| 52002 | sp_ConfirmPayment | Booking không ở trạng thái Pending | 409 |
| 52003 | sp_ConfirmPayment | Booking đã hết hạn giữ chỗ | 410 Gone |
| 52005 | sp_ConfirmPayment | Payment.Amount không khớp FinalAmount | 400 |
| 53001 | sp_ProcessRefund | PaymentID không tồn tại | 404 |
| 53004 | sp_ProcessRefund | Tổng Refund vượt Payment.Amount | 422 |
| 54006 | sp_ApplyPromotion | Promotion hết hiệu lực | 400 |
| 54009 | sp_ApplyPromotion | DiscountCode không hợp lệ | 400 |
| 55001 | sp_CancelBooking | Booking không tồn tại hoặc không thuộc Customer | 404 |
| 55002 | sp_CancelBooking | Booking không ở trạng thái Pending | 409 |
| 56001 | sp_InitiatePayment | Booking không tồn tại hoặc không thuộc Customer | 404 |
| 56002 | sp_InitiatePayment | Booking không ở trạng thái Pending | 409 |
| 56003 | sp_InitiatePayment | Đã có Payment Pending cho Booking này | 409 |
| 57001 | sp_RegisterUser | Username đã tồn tại | 409 |
| 57002 | sp_RegisterUser | Role Customer không tồn tại hoặc không Active | 500 |
| **2627** | DB Constraint | Duplicate Key — Webhook đã xử lý | **409** |
| *(khác)* | — | Lỗi DB không xác định | 500 |

### Response Body chuẩn (RFC 7807)

```json
{
  "type":     "https://api.concert.vn/errors/seat-unavailable",
  "title":    "Seat Unavailable",
  "status":   409,
  "detail":   "Một hoặc nhiều ghế bạn chọn đã được người khác đặt. Vui lòng chọn lại.",
  "instance": "/api/bookings",
  "traceId":  "0HN8LK2Q4KKF1:00000001"
}
```

---

## 12. Cấu Hình Kỹ Thuật

### 12.1 appsettings.json (cấu trúc)

```json
{
  "ConnectionStrings": {
    "Default": "Server=localhost\\SQLEXPRESS;Database=ConcertTicketingDB;User Id=api_service;Password=...;Max Pool Size=300;Min Pool Size=10;Connect Timeout=30;TrustServerCertificate=True;"
  },
  "Jwt": {
    "Secret":                   "your-256-bit-secret-key",
    "Issuer":                   "ConcertTicketingAPI",
    "Audience":                 "ConcertTicketingClient",
    "AccessTokenExpiryMinutes": 15,
    "RefreshTokenExpiryDays":   7
  },
  "Redis": {
    "Connection":        "localhost:6379",
    "SeatMapTtlSeconds": 15
  },
  "Serilog": {}
}
```

> [!IMPORTANT]
> **`Max Pool Size=300`**: Default của `Microsoft.Data.SqlClient` là 100. Với tải concurrent cao, pool 100 sẽ cạn kiệt → lỗi `Timeout expired obtaining a connection from the pool`. Điều chỉnh theo RAM SQL Server thực tế.

### 12.2 Dependency Registration (Program.cs)

```csharp
builder.Services.AddControllers();
builder.Services.AddFluentValidationAutoValidation();
builder.Services.AddValidatorsFromAssemblyContaining<CreateBookingValidator>();
builder.Services.AddOpenApi(options => { /* Bearer security scheme */ });
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(...);
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(...);
builder.Services.AddSingleton<IConnectionMultiplexer>(ConnectionMultiplexer.Connect(redis));
builder.Services.AddHangfire(...).AddHangfireServer();
builder.Services.AddScoped<IBookingRepository>(_ => new BookingRepository(connStr));
builder.Services.AddScoped<IConcertRepository>(_ => new ConcertRepository(connStr));
builder.Services.AddScoped<ICheckInRepository>(_ => new CheckInRepository(connStr));
builder.Services.AddScoped<IUserRepository>(_ => new UserRepository(connStr));
builder.Services.AddScoped<IPaymentRepository>(_ => new PaymentRepository(connStr));
builder.Services.AddScoped<IAuthService, AuthService>();
builder.Services.AddSingleton(sp => new SeatMapCache(redis, concertRepo, ttlSeconds));
builder.Services.AddHostedService(sp => new HoldReleaseWorker(connStr, logger));
builder.Services.AddHealthChecks().AddSqlServer(connStr).AddRedis(redisConn);
```

### 12.3 Health Check & API Docs

```
GET /healthz    -> Kiểm tra kết nối SQL Server + Redis
GET /scalar/v1  -> Chỉ Development (ScalarTheme.DeepSpace), hỗ trợ nhập JWT Bearer trực tiếp
```

---

## 13. Phạm Vi Triển Khai (Deployment Constraints)

Nhất quán với `database_plan.txt Section 23.7 (A22)`:

- **Single instance** ASP.NET Core Web API — không Load Balancer.
- **Single SQL Server instance** — không HA/Replication.
- **Single Redis instance** — `SemaphoreSlim` Mutex hoạt động đúng vì single-process.
- Nếu mở rộng lên nhiều instances: `SemaphoreSlim` trong `SeatMapCache` phải được thay thế bằng **Redis Distributed Lock** (`SET NX PX`).

---

## 14. Ghi Chú Quyết Định Kiến Trúc

| # | Quyết định | Lý do |
| :--- | :--- | :--- |
| A1 | `sp_RegisterUser` thay vì INSERT trực tiếp vào `UserAccount` | `api_service` bị DENY INSERT. SP đảm bảo tạo UserAccount + gán Role Customer + ghi Audit trong 1 transaction |
| A2 | `UserRepository.CreateRefreshTokenAsync` INSERT trực tiếp vào `RefreshToken` | Ngoại lệ có kiểm soát: SHA-256 hash tính trong C# từ raw token trong memory, không thể ủy quyền hợp lý cho SP |
| A3 | `SeatMapCache` dùng Redis (không dùng IMemoryCache) | Tuy single-instance, Redis dễ scale sau này và tách biệt memory với process API |
| A4 | `HoldReleaseWorker` query Concert list trước rồi gọi `sp_AllocateWaitlist` per Concert | SP yêu cầu `@ConcertID` — không có overload "all concerts" |
| A5 | `ErrorHandlingMiddleware` xử lý `2627` thành 409 thay vì 200 OK | Riêng Webhook Payment (`/api/payments/confirm`) nên bắt `SqlException 2627` trong controller và trả 200 OK để VNPay không retry |
| A6 | Không có `AdminController` | Quản lý Concert/Promotion/Seat do Organizer thực hiện qua các endpoint hiện tại. Chức năng Admin sẽ bổ sung trong phase sau |
| A7 | Refresh Token Rotation | Revoke token cũ trước khi cấp token mới — nếu token cũ bị đánh cắp và dùng lại sẽ phát hiện được |
