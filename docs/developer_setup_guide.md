# Hướng Dẫn Xây Dựng Dự Án Từ Đầu (Sequential Developer Guide)

Tài liệu này ghi lại chính xác các bước tuần tự mà một lập trình viên con người cần thực hiện để xây dựng hệ thống **Concert Ticketing Backend** từ một thư mục trống. Đã kiểm tra và đảm bảo không bỏ sót bất kỳ file source code nào trong tổng số 72 file SQL và 21 file C# hiện tại.

---

## Bước 1: Thiết Lập Môi Trường (Prerequisites)
1. Tải và cài đặt **.NET 9 SDK**.
2. Cài đặt **SQL Server** và SSMS/Azure Data Studio.
3. Cài đặt **Redis** (chạy local qua Docker hoặc cài trực tiếp trên Windows).

---

## Bước 2: Thiết Kế Cơ Sở Dữ Liệu (Tạo File SQL)
Tạo thư mục `database/` và tuần tự tạo 72 file SQL sau để định hình kiến trúc:

### 2.1. Khởi tạo Bảng (Tables)
Tạo thư mục `database/Tables/` và viết 26 file `.sql`:
- `Artist.sql`, `AuditRecord.sql`, `Booking.sql`, `BookingEventSeatAllocation.sql`, `BookingPromotionApplication.sql`
- `CheckIn.sql`, `CheckinStaffAssignment.sql`, `Concert.sql`, `DiscountCode.sql`, `EventSeat.sql`
- `Payment.sql`, `Promotion.sql`, `Queue.sql`, `QueueEntry.sql`, `Refund.sql`
- `Role.sql`, `Seat.sql`, `SystemConfiguration.sql`, `Ticket.sql`, `TicketCategory.sql`
- `UserAccount.sql`, `UserRoleAssignment.sql`, `Venue.sql`, `Waitlist.sql`, `WaitlistEntry.sql`, `Zone.sql`

*Ghi chú: Kèm theo bảng mở rộng ở Phase 2: `database/Scripts/AddRefreshTokenTable.sql`*

### 2.2. Viết Functions (Hàm Tính Toán)
Tạo thư mục `database/Functions/` và viết 3 file:
- `fn_CalculateBookingSubtotal.sql`
- `fn_CalculateFinalAmount.sql`
- `fn_GetCustomerTicketCount.sql`

### 2.3. Viết Stored Procedures (Luồng Nghiệp Vụ)
Tạo thư mục `database/StoredProcedures/` và viết 7 file:
- `sp_AllocateWaitlist.sql`
- `sp_ApplyPromotion.sql`
- `sp_CheckInTicket.sql`
- `sp_ConfirmPayment.sql`
- `sp_CreateBooking.sql`
- `sp_ProcessRefund.sql`
- `sp_ReleaseExpiredHolds.sql`

### 2.4. Viết Triggers (Bảo vệ dữ liệu toàn vẹn)
Tạo thư mục `database/Triggers/` và viết 14 file:
- `TRG_AllocationConcert.sql`, `TRG_AuditLog.sql`, `TRG_DiscountCodeConditional.sql`
- `TRG_EventSeatVenue.sql`, `TRG_InventoryAllocationConsistency.sql`
- `TRG_OneActiveTicketPerEventSeat.sql`, `TRG_PaymentConfirmedSingle.sql`
- `TRG_PromotionValidity.sql`, `TRG_RefundLimits.sql`, `TRG_SeatVenueConsistency.sql`
- `TRG_StateTransition.sql`, `TRG_SystemActorGuard.sql`
- `TRG_TicketConcertConsistency.sql`, `TRG_TicketCountOnConfirm.sql`

### 2.5. Viết Views (Báo cáo)
Tạo thư mục `database/Views/` và viết 2 file:
- `VW_ConcertSalesSummary.sql`
- `VW_Others.sql`

### 2.6. Viết Unit Tests (Kiểm thử Database)
Tạo thư mục `database/Tests/` và viết 14 file (gồm SQL và PowerShell):
- SQL: `00_TestFramework.sql`, `01_SetupMockData.sql`, `02_Test_Tables_Constraints.sql`, `03_Test_Triggers_StateMachine.sql`, `04_Test_Triggers_Integrity.sql`, `05_Test_Functions.sql`, `06_Test_Views.sql`, `07_Test_SP_CreateBooking.sql`, `08_Test_SP_ConfirmPayment.sql`, `09_Test_SP_Others.sql`, `10_Test_Security_Permissions.sql`, `11_Test_Concurrency.sql`, `Run-All-Tests.sql`
- PowerShell: `11_Test_Concurrency.ps1`, `Run-All-Tests.ps1`

### 2.7. Setup System Scripts
Tạo thư mục `database/Scripts/` và `database/Security/`:
- `CreateDatabase.sql`, `PostDeployment/SeedData.sql`, `setup_api_permissions.sql`
- `CreateDBUsers.sql`, `GrantPermissions.sql`
- Thư mục `database/Indexes/OperationalIndexes.sql`

---

## Bước 3: Thực Thi Cơ Sở Dữ Liệu

**Cách được khuyến nghị — chạy một lệnh duy nhất:**

```powershell
.\database\deploy.ps1 -ServerInstance ".\SQLEXPRESS" -DropExisting $true
```

`deploy.ps1` chạy đúng thứ tự phụ thuộc của toàn bộ 8 giai đoạn (Tables → Indexes → Functions
→ Triggers → Stored Procedures → Views → Hangfire → Security → Seed), tự sinh mật khẩu ngẫu
nhiên cho 5 SQL login và ghi ra `.deploy/db-credentials.json`. Đây là đường triển khai được
duy trì và kiểm chứng; chạy tay từng file rất dễ sai thứ tự.

**Nếu vẫn muốn chạy tay từng file:** `CreateDatabase.sql` nhận tên database qua biến sqlcmd
`$(DbName)` (để `deploy.ps1 -DatabaseName` có tác dụng), nên phải truyền biến đó:

```powershell
sqlcmd -S ".\SQLEXPRESS" -E -d master -i database\Scripts\CreateDatabase.sql -b -v DbName="ConcertTicketingDB"
```

Chạy thiếu `-v DbName=...` sẽ dừng ngay với lỗi `'DbName' scripting variable not defined` —
cố ý fail-loud để không âm thầm tạo nhầm database. Với SSMS phải bật **SQLCMD Mode**
(menu Query → SQLCMD Mode) thì `$(DbName)` mới được thay thế. Các bước còn lại:

1. Chạy toàn bộ file trong `database/Tables/`.
2. Chạy các file trong `database/Functions/`, `StoredProcedures/`, `Triggers/`, `Views/`.
3. Chạy script tạo Dữ liệu mẫu `SeedData.sql`.
4. Chạy `CreateDBUsers.sql` rồi `GrantPermissions.sql`.
5. Chạy `Run-All-Tests.ps1` để đảm bảo 100% test cases pass.

---

## Bước 4: Khởi Tạo Dự Án .NET
Chạy tuần tự các lệnh CLI:
```bash
dotnet new sln -n ConcertTicketing
dotnet new classlib -n ConcertTicketing.Domain
dotnet new classlib -n ConcertTicketing.Application
dotnet new classlib -n ConcertTicketing.Infrastructure
dotnet new webapi -n ConcertTicketing.API --no-openapi

dotnet sln add src/ConcertTicketing.Domain/ConcertTicketing.Domain.csproj
dotnet sln add src/ConcertTicketing.Application/ConcertTicketing.Application.csproj
dotnet sln add src/ConcertTicketing.Infrastructure/ConcertTicketing.Infrastructure.csproj
dotnet sln add src/ConcertTicketing.API/ConcertTicketing.API.csproj

dotnet add src/ConcertTicketing.Application/ConcertTicketing.Application.csproj reference src/ConcertTicketing.Domain/ConcertTicketing.Domain.csproj
dotnet add src/ConcertTicketing.Infrastructure/ConcertTicketing.Infrastructure.csproj reference src/ConcertTicketing.Application/ConcertTicketing.Application.csproj
dotnet add src/ConcertTicketing.API/ConcertTicketing.API.csproj reference src/ConcertTicketing.Infrastructure/ConcertTicketing.Infrastructure.csproj
dotnet add src/ConcertTicketing.API/ConcertTicketing.API.csproj reference src/ConcertTicketing.Application/ConcertTicketing.Application.csproj
```

---

## Bước 5: Cài Đặt Thư Viện (NuGet Packages)
```bash
# Infrastructure
dotnet add src/ConcertTicketing.Infrastructure package Dapper
dotnet add src/ConcertTicketing.Infrastructure package Microsoft.Data.SqlClient
dotnet add src/ConcertTicketing.Infrastructure package StackExchange.Redis
dotnet add src/ConcertTicketing.Infrastructure package BCrypt.Net-Next
dotnet add src/ConcertTicketing.Infrastructure package Hangfire.AspNetCore
dotnet add src/ConcertTicketing.Infrastructure package Hangfire.SqlServer

# Application
dotnet add src/ConcertTicketing.Application package FluentValidation

# API
dotnet add src/ConcertTicketing.API package Microsoft.AspNetCore.Authentication.JwtBearer
dotnet add src/ConcertTicketing.API package Microsoft.AspNetCore.OpenApi
dotnet add src/ConcertTicketing.API package Scalar.AspNetCore
dotnet add src/ConcertTicketing.API package Serilog.AspNetCore
dotnet add src/ConcertTicketing.API package Serilog.Sinks.Console
dotnet add src/ConcertTicketing.API package Serilog.Sinks.File
dotnet add src/ConcertTicketing.API package FluentValidation.AspNetCore
dotnet add src/ConcertTicketing.API package AspNetCore.HealthChecks.SqlServer
dotnet add src/ConcertTicketing.API package AspNetCore.HealthChecks.Redis
```

---

## Bước 6: Viết Code Tầng Domain (Core)
Tại `backend/src/ConcertTicketing.Domain/Models/`, tạo 4 file:
- `Booking.cs`
- `Concert.cs`
- `EventSeat.cs`
- `UserAccount.cs`

---

## Bước 7: Viết Code Tầng Application (Use Cases)
Tại `backend/src/ConcertTicketing.Application/`, tạo 4 file:
- `DTOs/Dtos.cs`
- `Interfaces/IRepositories.cs`
- `Services/AuthService.cs`
- `Validators/Validators.cs`

---

## Bước 8: Viết Code Tầng Infrastructure (Data Access)
Tại `backend/src/ConcertTicketing.Infrastructure/`, tạo 6 file:
- `BackgroundJobs/HoldReleaseWorker.cs`
- `Cache/SeatMapCache.cs`
- `Repositories/BookingRepository.cs`
- `Repositories/CheckInRepository.cs`
- `Repositories/ConcertRepository.cs`
- `Repositories/UserRepository.cs`

---

## Bước 9: Viết Code Tầng API (Presentation)
Tại `backend/src/ConcertTicketing.API/`, tạo 7 file:
- `Controllers/AuthController.cs`
- `Controllers/BookingController.cs`
- `Controllers/CheckInController.cs`
- `Controllers/ConcertController.cs`
- `HangfireAdminAuthFilter.cs`
- `Middleware/ErrorHandlingMiddleware.cs`
- `Program.cs`

---

## Bước 10: Biên Dịch & Chạy Thử
1. Chạy lệnh `dotnet build` tại thư mục root.
2. Chạy lệnh `dotnet run --project src/ConcertTicketing.API/ConcertTicketing.API.csproj`.
3. Mở trình duyệt truy cập `http://localhost:<port>/scalar/v1` để test các APIs.
