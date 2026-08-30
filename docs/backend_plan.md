# Ke Hoach Xay Dung Backend - Concert Ticketing System
*Production-grade Thin Backend cho Thick Database (SQL Server)*
*Version 3.0 - Authoritative. Moi quyet dinh kien truc phan anh dung 100% codebase.*

> [!IMPORTANT]
> Nguyen tac cot loi: **Backend khong tai trien khai bat ky Business Rule nao da co trong Database.** Moi thao tac ghi du lieu nghiep vu deu di qua Stored Procedures. Backend chi thuc hien: (1) Xac thuc JWT, (2) Validate DTO dau vao, (3) Goi SP/View qua Dapper, (4) Map ket qua/loi ra HTTP Response.

---

## 1. Kien Truc Tong The

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
  (PeriodicTimer 1 phut: sp_ReleaseExpiredHolds -> sp_AllocateWaitlist per Concert)
         |
         v
[ Hangfire Server ]  <- Email Job co Retry + Dashboard /hangfire
  (SendTicketEmailJob - persistence trong HangFire schema)
```

### Phan tang Backend

| Layer | Vai tro | Thu muc |
| :--- | :--- | :--- |
| **Presentation** | HTTP routing, JSON Serialize/Deserialize | `API/Controllers/` |
| **Application** | Auth orchestration, DTOs, Validators, Interfaces | `Application/` |
| **Data Access** | Dapper -> Stored Procedures / Views | `Infrastructure/Repositories/` |
| **Infrastructure** | Cache (Redis), Background Jobs | `Infrastructure/Cache/`, `Infrastructure/BackgroundJobs/` |
| **Domain** | C# Model classes anh xa tu DB Tables | `Domain/Models/` |

---

## 2. Tech Stack

| Muc | Cong nghe | Ghi chu |
| :--- | :--- | :--- |
| **Framework** | ASP.NET Core 9 (Web API) | Native voi SQL Server |
| **Data Access** | Dapper 2.x | Micro-ORM, goi SP tho khong can thiep Schema |
| **Validation** | FluentValidation + FluentValidation.AspNetCore | Auto-validation qua AddFluentValidationAutoValidation() |
| **Auth** | JWT Bearer (Microsoft.AspNetCore.Authentication.JwtBearer) | Stateless, RFC 7519, HMAC-SHA256 |
| **Password Hashing** | BCrypt.Net-Next (cost=12) | Self-salting, khong can cot PasswordSalt rieng |
| **Refresh Token** | SHA-256 (System.Security.Cryptography) | Raw token 64 bytes random, DB chi luu SHA-256 hex hash |
| **Rate Limiting** | Microsoft.AspNetCore.RateLimiting (built-in ASP.NET Core 9) | SlidingWindow + FixedWindow |
| **Cache** | Redis (StackExchange.Redis) + SemaphoreSlim Mutex | TTL + Single-Flight chong Cache Stampede |
| **Background Job (critical)** | Hangfire (Hangfire.SqlServer) | Email ve - retry + persistence + dashboard |
| **Background Job (periodic)** | IHostedService + PeriodicTimer | sp_ReleaseExpiredHolds + sp_AllocateWaitlist moi 1 phut |
| **Logging** | Serilog (ReadFrom.Configuration + ReadFrom.Services) | Structured logging |
| **API Docs** | Scalar (ScalarTheme.DeepSpace) + ASP.NET Core OpenAPI | Chi Development |
| **DB Client** | Microsoft.Data.SqlClient | |
| **Testing** | xUnit + Testcontainers | Unit test + Integration test voi DB that |

> [!NOTE]
> **Tai sao dung ca Hangfire lan IHostedService?**
> - `IHostedService (HoldReleaseWorker)`: Job dinh ky don gian, idempotent. App restart thi SP chay lai o chu ky tiep theo la OK. Khong can persistence hay retry.
> - `Hangfire (SendTicketEmailJob)`: Job nghiep vu quan trong. App restart giua luc gui email thi Hangfire tu retry tu DB. IHostedService se mat job do vinh vien.

> [!IMPORTANT]
> **Hangfire dung `PrepareSchemaIfNecessary = false`.** Schema HangFire phai duoc tao truoc qua `database/Scripts/HangfireSchema.sql` trong `deploy.ps1`. Backend khong tu tao schema.

---

## 3. Cau Truc Thu Muc

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
|   |   +-- HangfireAdminAuthFilter.cs   # Bao ve /hangfire dashboard
|   |   +-- Program.cs                   # DI, Middleware pipeline, Config
|   |
|   +-- ConcertTicketing.Application/
|   |   +-- DTOs/Dtos.cs                 # Tat ca Request/Response records
|   |   +-- Interfaces/IRepositories.cs  # Interface contracts cho 5 Repositories
|   |   +-- Services/AuthService.cs      # BCrypt.Verify, JWT generate, Refresh Token
|   |   +-- Validators/Validators.cs     # FluentValidation cho moi Request DTO
|   |
|   +-- ConcertTicketing.Infrastructure/
|   |   +-- BackgroundJobs/
|   |   |   +-- HoldReleaseWorker.cs     # IHostedService: sp_ReleaseExpiredHolds + sp_AllocateWaitlist
|   |   |   +-- SendTicketEmailJob.cs    # Hangfire Job: gui email co retry
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

Tat ca DTOs la C# `record` (immutable). Dinh nghia tap trung trong `Application/DTOs/Dtos.cs`.

### 4.1 Auth DTOs

```csharp
record LoginRequest(string Username, string Password);

record RegisterRequest(string Username, string Email, string Password, string DisplayName);

// RefreshToken KHONG tra trong body - duoc set qua HttpOnly Cookie
record AuthResponse(string AccessToken, string TokenType, int ExpiresIn);
// TokenType luon la "Bearer", ExpiresIn = AccessTokenExpiryMinutes * 60
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
// Empty body - BookingID lay tu URL, CustomerID lay tu JWT
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

### 4.6 Phan trang

```csharp
record PagedResult<T>(IEnumerable<T> Items, int TotalCount, int Page, int PageSize)
{
    public int TotalPages => (int)Math.Ceiling((double)TotalCount / PageSize);
}
```

---

## 5. FluentValidation Rules

Tat ca Validators trong `Application/Validators/Validators.cs`. Auto-validation bat qua `AddFluentValidationAutoValidation()`.

| Validator | Rules |
| :--- | :--- |
| `LoginValidator` | Username: NotEmpty max 100; Password: NotEmpty min 6 |
| `RegisterValidator` | Username: 3-50 ky tu regex `^[a-zA-Z0-9_]+$`; Email: dinh dang hop le; Password: min 8 co chu hoa + so; DisplayName: NotEmpty max 200 |
| `CreateBookingValidator` | ConcertId > 0; SeatIds: NotEmpty toi da 10 ghe khong trung lap moi ID > 0 |
| `ApplyPromotionValidator` | DiscountCode: NotEmpty max 50 |
| `CheckInValidator` | TicketCode: NotEmpty max 100; ConcertId > 0 |

---

## 6. Repository Interfaces

Dinh nghia trong `Application/Interfaces/IRepositories.cs`. Implementation trong `Infrastructure/Repositories/`.

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
    Task<InitiatePaymentResponse> InitiateAsync(int bookingId, int customerUserId);               // -> sp_InitiatePayment
    Task ConfirmAsync(int bookingId, int paymentId, string? providerReference);                   // -> sp_ConfirmPayment
    Task<int> ProcessRefundAsync(int paymentId, decimal amount, string reason, int actorUserId);  // -> sp_ProcessRefund
}
```

---

## 7. Thiet Ke API Endpoints

### 7.1 Authentication (/api/auth)

> Backend xu ly toan bo logic Auth. DB chi luu PasswordHash (BCrypt, self-salting) va SHA-256(RefreshToken).

```
POST /api/auth/register  -> sp_RegisterUser (qua UserRepository.CreateAsync)
POST /api/auth/login     -> SELECT UserAccount + BCrypt.Verify + phat JWT Pair
POST /api/auth/refresh   -> ValidateRefreshToken (SHA-256) + Rotation + phat JWT Pair moi
POST /api/auth/logout    -> RevokeRefreshToken (SET IsRevoked=1, khong DELETE)
```

**Luong Register:**
1. FluentValidation: Username regex `^[a-zA-Z0-9_]+$`, Password min 8 + uppercase + digit.
2. `AuthService.RegisterAsync()` -> `BCrypt.HashPassword(password, cost=12)`.
3. `UserRepository.CreateAsync()` -> `EXEC sp_RegisterUser @Username, @Email, @PasswordHash, @DisplayName, @NewUserID OUTPUT`.
4. SP tu tao UserAccount + gan Role Customer + ghi AuditRecord trong 1 transaction.
5. Phat JWT Access Token + Refresh Token qua HttpOnly Cookie.

**Luong Login:**
1. `UserRepository.GetByUsernameAsync()` -> `SELECT ... FROM UserAccount WHERE Username=@Username AND AccountStatus='Active'`.
2. `BCrypt.Verify(password, storedHash)` -> neu sai throw UnauthorizedAccessException.
3. `UserRepository.GetRolesAsync()` -> `SELECT r.RoleName FROM UserRoleAssignment ... WHERE AssignmentStatus='Active' AND RoleStatus='Active'`.
4. `GenerateAccessToken()` -> JWT chua `{ sub: UserID, jti: Guid, email, displayName, roles[] }`, HMAC-SHA256.
5. `CreateRefreshTokenAsync()` -> raw token 64 bytes (`RandomNumberGenerator.GetBytes(64)`) -> SHA-256 hex -> INSERT RefreshToken table.
6. Tra ve `AuthResponse(AccessToken, "Bearer", ExpiresIn)` + set HttpOnly Cookie.

**Refresh Token Cookie:**
```csharp
Response.Cookies.Append("refreshToken", rawToken, new CookieOptions {
    HttpOnly = true,
    Secure   = Request.IsHttps,
    SameSite = SameSiteMode.Strict,
    Expires  = DateTimeOffset.UtcNow.AddDays(RefreshTokenExpiryDays),
    Path     = "/api/auth"  // Chi gui den /api/auth/* - gioi han pham vi toi da
});
```

**Luong Refresh (Refresh Token Rotation):**
1. Doc raw token tu HttpOnly Cookie.
2. SHA-256 hex -> query `RefreshToken WHERE TokenHash=? AND ExpiryDatetime > SYSUTCDATETIME() AND IsRevoked=0`.
3. `RevokeRefreshTokenAsync()` -> `SET IsRevoked=1` (khong DELETE, giu audit trail).
4. Phat JWT Pair moi.

---

### 7.2 Concerts (/api/concerts) - Public, khong can Auth

```
GET /api/concerts              -> SELECT Concert + Artist + Venue (Filter, Pagination)
GET /api/concerts/{id}         -> Chi tiet Concert
GET /api/concerts/{id}/seats   -> Danh sach EventSeat (qua SeatMapCache)
```

**Pagination mac dinh:** `page=1`, `pageSize=20` (max 100).

**Cache Strategy - GET /concerts/{id}/seats (SeatMapCache):**

```csharp
// SeatMapCache.cs - TTL 15s + SemaphoreSlim(1,1) Mutex
public async Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId, CancellationToken ct)
{
    var cacheKey = $"concert:seats:{concertId}";

    // Fast path: cache hit
    var cached = await _redis.StringGetAsync(cacheKey);
    if (cached.HasValue) return Deserialize(cached);

    // Slow path: chi 1 luong duoc vao DB, cac luong khac cho (khong ban DB cung luc)
    await _lock.WaitAsync(ct);
    try
    {
        // Double-check sau khi vao lock
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
> TTL co the cau hinh qua `Redis:SeatMapTtlSeconds` trong appsettings.json (default 15).
> `SemaphoreSlim` chi hoat dong trong 1 process. Neu scale len nhieu instances, phai chuyen sang Redis Distributed Lock (`SET NX PX`).

> [!NOTE]
> **Khong dung explicit cache invalidation.** Cache tu het han sau TTL. Chap nhan du lieu tre 15s - trade-off tranh Cache Stampede khi concert co hang chuc nghin nguoi xem dong thoi.

---

### 7.3 Bookings (/api/bookings) - [Authorize]

```
POST   /api/bookings                  -> EXEC sp_CreateBooking    [Role: Customer] [RateLimit: booking]
GET    /api/bookings/{id}             -> SELECT Booking + Allocations (CustomerID filter tu JWT)
POST   /api/bookings/{id}/promotion   -> EXEC sp_ApplyPromotion   [Role: Customer]
DELETE /api/bookings/{id}             -> EXEC sp_CancelBooking    [Role: Customer]
```

**Luong POST /api/bookings:**
1. JWT Middleware -> Lay CustomerUserID tu ClaimTypes.NameIdentifier. KHONG BAO GIO lay tu Request Body.
2. FluentValidation tu dong: ConcertId > 0, SeatIds hop le.
3. Rate Limit [EnableRateLimiting("booking")]: 2 req/10s per UserID - chong double-click.
4. `BookingRepository.CreateAsync(userId, request)` -> `EXEC sp_CreateBooking @CustomerUserID, @ConcertID, @SeatList='101,102', @WaitlistEntryID, @NewBookingID OUTPUT`.
5. Tra ve 201 Created voi CreateBookingResponse.

**Luong DELETE /api/bookings/{id}:**
1. `BookingRepository.CancelAsync(id, userId)` -> `EXEC sp_CancelBooking @BookingID, @CustomerUserID`.
2. SP chi cancel Booking o trang thai Pending. Confirmed Booking co luong xu ly rieng biet.
3. Tra ve 204 No Content.

---

### 7.4 Payments - [Authorize]

```
POST /api/bookings/{bookingId}/payment  -> EXEC sp_InitiatePayment  [Role: Customer]
POST /api/payments/confirm              -> EXEC sp_ConfirmPayment    [AllowAnonymous - Webhook]
POST /api/payments/{paymentId}/refund   -> EXEC sp_ProcessRefund     [Role: Admin, Organizer]
```

**Luong Thanh Toan Hoan Chinh:**
```
[Frontend]           [Backend]              [VNPay]           [DB]
    |--POST /payment->|                       |                |
    |                 |--EXEC sp_InitiatePayment-------------->|
    |                 |  SP tu sinh PaymentReference = 'PAY-'+NEWID()
    |                 |  SP INSERT Payment Status='Pending'    |
    |                 |<-- PaymentID, Ref, Amount -------------|
    |                 |-- VNPay.CreatePaymentUrl() ----------->|
    |<-- paymentUrl --|                       |                |
    |-- Redirect ------------------------------>               |
    |                 |<--- POST /confirm ----|                |
    |                 |  ?bookingId=&paymentId=&vnp_TransactionNo=
    |                 |-- EXEC sp_ConfirmPayment ------------->|
    |                 |<-- OK ---------------------------------|
    |                 |-- Hangfire.Enqueue(SendTicketEmailJob)
    |                 |-- 200 OK ----------->|                |
```

**Webhook POST /api/payments/confirm:**
- [AllowAnonymous] - VNPay khong gui JWT.
- Nhan parameters tu query string: bookingId, paymentId, vnp_TransactionNo.
- Goi `PaymentRepository.ConfirmAsync(bookingId, paymentId, vnp_TransactionNo)`.
- Sau confirm thanh cong: `Hangfire.Enqueue<SendTicketEmailJob>`.
- Luon tra 200 OK de VNPay khong retry vo han.

> [!IMPORTANT]
> **sp_InitiatePayment tu sinh PaymentReference** ben trong SP dung NEWID(). Backend khong tu sinh va truyen vao - api_service bi DENY INSERT truc tiep tren bang Payment.

---

### 7.5 Check-In (/api/checkin) - [Authorize(Roles = "Staff")]

```
POST /api/checkin   -> EXEC sp_CheckInTicket [Role: Staff] [RateLimit: checkin]
```

**Luong Check-In:**
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

- SP tu xu ly toan bo logic va Audit (ke ca khi INVALID/ALREADY_USED).
- Luon tra 200 OK - Frontend dung ValidationResult de hien thi mau xanh/do.

> [!NOTE]
> Role trong JWT la "Staff" (ten claim), anh xa tu ten role "Check-in Staff" trong DB. AuthService.GenerateAccessToken() phai map dung ten role tu DB sang claim.

---

## 8. Background Jobs

### 8.1 HoldReleaseWorker (IHostedService - PeriodicTimer)

```csharp
// HoldReleaseWorker.cs
protected override async Task ExecuteAsync(CancellationToken stoppingToken)
{
    using var timer = new PeriodicTimer(TimeSpan.FromMinutes(1));
    while (await timer.WaitForNextTickAsync(stoppingToken))
    {
        try { await ReleaseAndAllocateAsync(stoppingToken); }
        catch (OperationCanceledException) { break; }      // App shutdown binh thuong
        catch (Exception ex) { _logger.LogError(ex, ...); } // Tiep tuc, khong crash worker
    }
}

private async Task ReleaseAndAllocateAsync(CancellationToken ct)
{
    using var conn = new SqlConnection(_connectionString);
    await conn.OpenAsync(ct);

    // Buoc 1: Nha ghe het han -> Available
    await conn.ExecuteAsync(
        "sp_ReleaseExpiredHolds", commandType: CommandType.StoredProcedure, cancellationToken: ct);

    // Buoc 2: Lay danh sach Concert dang OnSale
    var concertIds = await conn.QueryAsync<int>(
        "SELECT ConcertID FROM Concert WHERE ConcertStatus = 'OnSale' AND SalesPaused = 0",
        cancellationToken: ct);

    // Buoc 3: Goi sp_AllocateWaitlist(@ConcertID) cho tung Concert
    foreach (var concertId in concertIds)
    {
        await conn.ExecuteAsync("sp_AllocateWaitlist",
            new { ConcertID = concertId },
            commandType: CommandType.StoredProcedure, cancellationToken: ct);
    }
}
```

> [!IMPORTANT]
> sp_AllocateWaitlist **bat buoc nhan @ConcertID** lam tham so. Worker phai truy van danh sach Concert OnSale va goi SP cho tung Concert rieng le.

### 8.2 SendTicketEmailJob (Hangfire)

```csharp
// Enqueue ngay sau khi sp_ConfirmPayment thanh cong
BackgroundJob.Enqueue<SendTicketEmailJob>(j => j.ExecuteAsync(bookingId, CancellationToken.None));
```

- Hangfire dung SQL Server storage (schema HangFire), PrepareSchemaIfNecessary = false.
- Retry voi Exponential Backoff neu SendGrid timeout.
- Dashboard tai /hangfire - bao ve boi HangfireAdminAuthFilter (chi role Admin).

---

## 9. Bao Mat

### 9.1 JWT Claims Structure

```json
{
  "sub":         "157",
  "jti":         "550e8400-e29b-41d4-a716-446655440000",
  "email":       "user@example.com",
  "displayName": "Nguyen Van A",
  "roles":       ["Customer"],
  "iss":         "ConcertTicketingAPI",
  "aud":         "ConcertTicketingClient",
  "exp":         1725000000
}
```

- `sub` = UserID (int, dang string theo RFC 7519). Controller doc bang `User.FindFirstValue(ClaimTypes.NameIdentifier)`.
- `jti` = Guid.NewGuid() - unique per token.

### 9.2 Authorization - Role-Based

| Endpoint | Roles duoc phep |
| :--- | :--- |
| `POST /api/auth/*` | AllowAnonymous |
| `GET /api/concerts/*` | AllowAnonymous |
| `POST /api/bookings` | Customer |
| `GET /api/bookings/{id}` | Authorize (bat ky user da dang nhap) |
| `POST /api/bookings/{id}/promotion` | Customer |
| `DELETE /api/bookings/{id}` | Customer |
| `POST /api/bookings/{bookingId}/payment` | Customer |
| `POST /api/payments/confirm` | AllowAnonymous (Webhook) |
| `POST /api/payments/{id}/refund` | Admin, Organizer |
| `POST /api/checkin` | Staff |
| `GET /hangfire` | Admin (HangfireAdminAuthFilter) |

### 9.3 Rate Limiting (Built-in ASP.NET Core 9)

```csharp
builder.Services.AddRateLimiter(options => {
    // booking: chong double-click - per UserID (Sliding Window)
    options.AddSlidingWindowLimiter("booking", opt => {
        opt.Window            = TimeSpan.FromSeconds(10);
        opt.PermitLimit       = 2;
        opt.SegmentsPerWindow = 2;
    });
    // auth: chong Brute Force - per IP (Fixed Window)
    options.AddFixedWindowLimiter("auth", opt => {
        opt.Window      = TimeSpan.FromMinutes(1);
        opt.PermitLimit = 5;
    });
    // checkin: chong quet ma ve - per Staff UserID (Fixed Window)
    options.AddFixedWindowLimiter("checkin", opt => {
        opt.Window      = TimeSpan.FromSeconds(1);
        opt.PermitLimit = 10;
    });
    options.OnRejected = async (ctx, _) => {
        ctx.HttpContext.Response.StatusCode = 429;
        await ctx.HttpContext.Response.WriteAsJsonAsync(
            new { error = "Qua nhieu yeu cau. Vui long thu lai sau." });
    };
});
```

> [!IMPORTANT]
> Rate Limiter phai dat SAU UseAuthentication() va UseAuthorization() trong pipeline. Neu dat truoc, UserID-based limiter se khong co Claims va fall back sang IP-based.

### 9.4 SQL Injection Prevention - Dapper DynamicParameters

```csharp
// Vi du: BookingRepository.CreateAsync()
var p = new DynamicParameters();
p.Add("@CustomerUserID", customerUserId,                     DbType.Int32);
p.Add("@ConcertID",      request.ConcertId,                  DbType.Int32);
p.Add("@SeatList",       string.Join(",", request.SeatIds),  DbType.String, size: -1);
p.Add("@WaitlistEntryID", request.WaitlistEntryId,           DbType.Int32);
p.Add("@NewBookingID",   dbType: DbType.Int32, direction: ParameterDirection.Output);

await conn.ExecuteAsync("sp_CreateBooking", p, commandType: CommandType.StoredProcedure);
var bookingId = p.Get<int>("@NewBookingID");
```

Toan bo queries dung Parameterized Query. Khong co string concatenation SQL.

### 9.5 Phan Quyen Database (Principle of Least Privilege)

api_service duoc cau hinh trong `database/Security/GrantPermissions.sql`:

```sql
-- GRANT: Thuc thi toan bo SPs + SELECT toan bo schema dbo
GRANT EXECUTE ON SCHEMA::dbo TO api_service;
GRANT SELECT  ON SCHEMA::dbo TO api_service;

-- GRANT ngoai le: RefreshToken (C# thao tac truc tiep cho Auth)
GRANT INSERT, UPDATE ON dbo.RefreshToken TO api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[HangFire] TO api_service;

-- DENY tuyet doi (Core Business Tables - bat buoc qua SP)
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
> Bang RefreshToken la ngoai le duy nhat duoc C# thao tac truc tiep (khong qua SP). Ly do: SHA-256 hash tinh trong C# tu raw token chi ton tai trong memory cua backend - khong the uy quyen hop ly cho SP.

---

## 10. Middleware Pipeline

Thu tu trong Program.cs (quan trong - sai thu tu gay loi tinh vi):

```
 1. ForwardedHeaders (XForwardedFor, XForwardedProto)  <- Doc IP that tu Nginx
 2. UseSerilogRequestLogging()                          <- Log moi request
 3. UseMiddleware<ErrorHandlingMiddleware>()             <- Bao boc toan bo pipeline
 4. UseHttpsRedirection()                               <- Chi non-Development
 5. UseRouting()                                        <- Xac dinh route
 6. UseAuthentication()                                 <- Giai ma JWT Claims
 7. UseAuthorization()                                  <- Kiem tra Roles/Policies
 8. UseRateLimiter()                                    <- Sau Auth de dung UserID
 9. MapControllers()
10. MapHangfireDashboard("/hangfire")                   <- Bao ve boi HangfireAdminAuthFilter
11. MapOpenApi() + MapScalarApiReference()              <- Chi Development
12. MapHealthChecks("/healthz")                         <- Kiem tra DB + Redis
```

---

## 11. Xu Ly Loi Chuan Hoa (Error Handling)

ErrorHandlingMiddleware bat toan bo exception, map sang RFC 7807 Problem Details.

### Mapping SqlException.Number -> HTTP Status Code

| SQL Error | Nguon SP | Y nghia | HTTP |
| :--- | :--- | :--- | :--- |
| 51001 | sp_CreateBooking | Concert khong OnSale hoac SalesPaused | 400 |
| 51002 | sp_CreateBooking | SeatList rong | 400 |
| 51003 | sp_CreateBooking | Vuot Purchase Limit | 422 |
| 51004 | sp_CreateBooking | Ghe khong con kha dung (race condition) | 409 |
| 51005 | sp_CreateBooking | WaitlistEntry khong hop le hoac het han | 400 |
| 52001 | sp_ConfirmPayment | BookingID khong ton tai | 404 |
| 52002 | sp_ConfirmPayment | Booking khong o trang thai Pending | 409 |
| 52003 | sp_ConfirmPayment | Booking da het han giu cho | 410 Gone |
| 52005 | sp_ConfirmPayment | Payment.Amount khong khop FinalAmount | 400 |
| 53001 | sp_ProcessRefund | PaymentID khong ton tai | 404 |
| 53004 | sp_ProcessRefund | Tong Refund vuot Payment.Amount | 422 |
| 54006 | sp_ApplyPromotion | Promotion het hieu luc | 400 |
| 54009 | sp_ApplyPromotion | DiscountCode khong hop le | 400 |
| 55001 | sp_CancelBooking | Booking khong ton tai hoac khong thuoc Customer | 404 |
| 55002 | sp_CancelBooking | Booking khong o trang thai Pending | 409 |
| 56001 | sp_InitiatePayment | Booking khong ton tai hoac khong thuoc Customer | 404 |
| 56002 | sp_InitiatePayment | Booking khong o trang thai Pending | 409 |
| 56003 | sp_InitiatePayment | Da co Payment Pending cho Booking nay | 409 |
| 57001 | sp_RegisterUser | Username da ton tai | 409 |
| 57002 | sp_RegisterUser | Role Customer khong ton tai hoac khong Active | 500 |
| **2627** | DB Constraint | Duplicate Key - Webhook da xu ly | **409** |
| *(khac)* | --- | Loi DB khong xac dinh | 500 |

### Response Body chuan (RFC 7807)

```json
{
  "type":     "https://api.concert.vn/errors/seat-unavailable",
  "title":    "Seat Unavailable",
  "status":   409,
  "detail":   "Mot hoac nhieu ghe ban chon da duoc nguoi khac dat. Vui long chon lai.",
  "instance": "/api/bookings",
  "traceId":  "0HN8LK2Q4KKF1:00000001"
}
```

---

## 12. Cau Hinh Ky Thuat

### 12.1 appsettings.json (cau truc)

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
> **Max Pool Size=300**: Default cua Microsoft.Data.SqlClient la 100. Voi tai concurrent cao, pool 100 se can kiet -> loi "Timeout expired obtaining a connection from the pool". Dieu chinh theo RAM SQL Server thuc te.

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

### 12.3 Health Check

```
GET /healthz  -> Kiem tra ket noi SQL Server + Redis
```

### 12.4 Scalar API Documentation

```
GET /scalar/v1  -> Chi trong Development (ScalarTheme.DeepSpace)
                   Ho tro nhap JWT Bearer token truc tiep tren UI
```

---

## 13. Pham Vi Trien Khai (Deployment Constraints)

Nhat quan voi database_plan.txt Section 23.7 (A22):

- **Single instance** ASP.NET Core Web API - khong Load Balancer.
- **Single SQL Server instance** - khong HA/Replication.
- **Single Redis instance** - SemaphoreSlim Mutex hoat dong dung vi single-process.
- Neu mo rong len nhieu instances: SemaphoreSlim trong SeatMapCache phai duoc thay the bang Redis Distributed Lock (`SET NX PX`).

---

## 14. Ghi Chu Quyet Dinh Kien Truc

| # | Quyet dinh | Ly do |
| :--- | :--- | :--- |
| A1 | sp_RegisterUser thay vi INSERT truc tiep vao UserAccount | api_service bi DENY INSERT. SP dam bao tao UserAccount + gan Role Customer + ghi Audit trong 1 transaction |
| A2 | UserRepository.CreateRefreshTokenAsync INSERT truc tiep vao RefreshToken | Ngoai le co kiem soat: SHA-256 hash tinh trong C# tu raw token trong memory, khong the uy quyen hop ly cho SP |
| A3 | SeatMapCache dung Redis (khong dung IMemoryCache) | Tuy single-instance, Redis de scale sau nay va tach biet memory voi process API |
| A4 | HoldReleaseWorker query Concert list truoc roi goi sp_AllocateWaitlist per Concert | SP yeu cau @ConcertID - khong co overload "all concerts" |
| A5 | ErrorHandlingMiddleware xu ly 2627 thanh 409 thay vi 200 OK | Rieng Webhook Payment (/api/payments/confirm) nen bat SqlException 2627 trong controller va tra 200 OK de VNPay khong retry |
| A6 | Khong co AdminController | Quan ly Concert/Promotion/Seat do Organizer thuc hien qua cac endpoint hien tai. Chuc nang Admin se bo sung trong phase sau |
| A7 | Refresh Token Rotation | Revoke token cu truoc khi cap token moi - neu token cu bi danh cap va dung lai se phat hien duoc |
