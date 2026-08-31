-- =============================================================
-- Script: Khởi tạo DB User cho Backend API (Principle of Least Privilege)
-- Database: ConcertTicketingDB
-- Mục đích: Tạo login `api_service` với quyền tối thiểu cần thiết.
--   - EXECUTE: Chỉ trên các Stored Procedures (Business Logic)
--   - SELECT:  Chỉ trên Views và Tables chỉ-đọc (GET endpoints)
--   - KHÔNG CÓ: INSERT/UPDATE/DELETE trực tiếp trên bất kỳ Table nào
-- =============================================================

USE [ConcertTicketingDB];
GO

-- ---------------------------------------------------------------
-- 1. Tạo Login ở cấp SQL Server Instance
-- ---------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = N'api_service')
BEGIN
    -- THAY 'YourStrongPassword!' bằng mật khẩu thực tế, lưu vào Secret Manager
    CREATE LOGIN [api_service] WITH PASSWORD = N'YourStrongPassword!';
    PRINT 'LOGIN api_service created.';
END
ELSE
    PRINT 'LOGIN api_service already exists.';
GO

-- ---------------------------------------------------------------
-- 2. Tạo User trong Database
-- ---------------------------------------------------------------
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'api_service')
BEGIN
    CREATE USER [api_service] FOR LOGIN [api_service];
    PRINT 'USER api_service created.';
END
ELSE
    PRINT 'USER api_service already exists.';
GO

-- ---------------------------------------------------------------
-- 3. Cấp quyền EXECUTE trên Stored Procedures (Business Logic)
--    Ownership Chaining: các SP này gọi bảng cùng owner (dbo),
--    nên không cần GRANT SELECT riêng cho các bảng mà SP truy cập.
-- ---------------------------------------------------------------
GRANT EXECUTE ON dbo.[sp_CreateBooking]        TO [api_service];
GRANT EXECUTE ON dbo.[sp_ConfirmPayment]       TO [api_service];
GRANT EXECUTE ON dbo.[sp_ApplyPromotion]       TO [api_service];
GRANT EXECUTE ON dbo.[sp_CheckInTicket]        TO [api_service];
GRANT EXECUTE ON dbo.[sp_ProcessRefund]        TO [api_service];
GRANT EXECUTE ON dbo.[sp_ReleaseExpiredHolds]  TO [api_service];
GRANT EXECUTE ON dbo.[sp_AllocateWaitlist]     TO [api_service];
GRANT EXECUTE ON dbo.[sp_RegisterUser]         TO [api_service];
GRANT EXECUTE ON dbo.[sp_CancelBooking]        TO [api_service];
GRANT EXECUTE ON dbo.[sp_InitiatePayment]      TO [api_service];

-- Admin / Organizer management (AdminController)
GRANT EXECUTE ON dbo.[sp_CreateConcert]              TO [api_service];
GRANT EXECUTE ON dbo.[sp_UpdateConcert]              TO [api_service];
GRANT EXECUTE ON dbo.[sp_UpdateConcertStatus]        TO [api_service];
GRANT EXECUTE ON dbo.[sp_CreateVenue]                TO [api_service];
GRANT EXECUTE ON dbo.[sp_CreateZone]                 TO [api_service];
GRANT EXECUTE ON dbo.[sp_CreateSeat]                 TO [api_service];
GRANT EXECUTE ON dbo.[sp_ConfigureTicketCategory]    TO [api_service];
GRANT EXECUTE ON dbo.[sp_AddEventSeats]              TO [api_service];
GRANT EXECUTE ON dbo.[sp_CreatePromotion]            TO [api_service];
GRANT EXECUTE ON dbo.[sp_AssignRole]                 TO [api_service];

-- Admin extended management (prepared, spec BR)
GRANT EXECUTE ON dbo.[sp_CreateDiscountCode]         TO [api_service];
GRANT EXECUTE ON dbo.[sp_SetEventSeatUnavailable]    TO [api_service];
GRANT EXECUTE ON dbo.[sp_AdminUpdateUserStatus]      TO [api_service];
GRANT EXECUTE ON dbo.[sp_AddCheckinStaffAssignment]  TO [api_service];

-- Customer self-service / Fair Access (Waitlist + Queue)
GRANT EXECUTE ON dbo.[sp_JoinWaitlist]               TO [api_service];
GRANT EXECUTE ON dbo.[sp_JoinQueue]                  TO [api_service];

PRINT '26 Stored Procedure EXECUTE permissions granted.';
GO

-- ---------------------------------------------------------------
-- 4. Cấp quyền SELECT trên Views (Dapper đọc trực tiếp, không qua SP)
-- ---------------------------------------------------------------
GRANT SELECT ON dbo.[VW_ConcertSalesSummary]     TO [api_service];
GRANT SELECT ON dbo.[VW_CheckInReport]           TO [api_service];
GRANT SELECT ON dbo.[VW_CustomerBookingHistory]  TO [api_service];
GRANT SELECT ON dbo.[VW_WaitlistQueue]           TO [api_service];
-- KHONG grant VW_AuditTrail: view nay doc AuditRecord, ma truy cap AuditRecord
-- bi DENY (chi Admin duoc doc). Grant view se vo hieu hoa DENY qua ownership chaining.

PRINT 'View SELECT permissions granted.';
GO

-- ---------------------------------------------------------------
-- 5. Cấp quyền SELECT trên Tables chỉ-đọc (GET /concerts, /seats...)
--    Mọi WRITE phải đi qua Stored Procedures.
-- ---------------------------------------------------------------
GRANT SELECT ON dbo.[Concert]             TO [api_service];
GRANT SELECT ON dbo.[Artist]              TO [api_service];
GRANT SELECT ON dbo.[Venue]              TO [api_service];
GRANT SELECT ON dbo.[EventSeat]           TO [api_service];
GRANT SELECT ON dbo.[Booking]            TO [api_service];
GRANT SELECT ON dbo.[BookingEventSeatAllocation] TO [api_service];
GRANT SELECT ON dbo.[Ticket]             TO [api_service];
GRANT SELECT ON dbo.[Payment]            TO [api_service];
GRANT SELECT ON dbo.[UserAccount]        TO [api_service];  -- Auth: đọc PasswordHash
GRANT SELECT ON dbo.[UserRoleAssignment] TO [api_service];  -- Auth: đọc Roles
GRANT SELECT ON dbo.[Role]              TO [api_service];   -- Auth: tên Role
GRANT SELECT ON dbo.[Promotion]         TO [api_service];
GRANT SELECT ON dbo.[Waitlist]          TO [api_service];
GRANT SELECT ON dbo.[WaitlistEntry]     TO [api_service];   -- WaitlistRepository (Join/GetMyEntry đọc trực tiếp)
GRANT SELECT ON dbo.[Queue]             TO [api_service];   -- QueueRepository (GetMyEntry JOIN)
GRANT SELECT ON dbo.[QueueEntry]        TO [api_service];   -- QueueRepository (Join/GetMyEntry đọc trực tiếp)
GRANT SELECT ON dbo.[Payment]           TO [api_service];   -- PaymentRepository (HMAC verify: đọc Amount/Status)
GRANT SELECT ON dbo.[TicketCategory]     TO [api_service];   -- (trước đây ghi nhầm SeatCategory/TicketType - không tồn tại)

PRINT 'Table SELECT permissions granted.';
GO

-- ---------------------------------------------------------------
-- 6. Xác nhận toàn bộ quyền đã cấp cho api_service
-- ---------------------------------------------------------------
SELECT
    dp.class_desc                AS [Object Type],
    OBJECT_NAME(dp.major_id)    AS [Object Name],
    dp.permission_name           AS [Permission],
    dp.state_desc                AS [Grant State],
    usr.name                    AS [Grantee]
FROM sys.database_permissions dp
JOIN sys.database_principals  usr ON dp.grantee_principal_id = usr.principal_id
WHERE usr.name = N'api_service'
ORDER BY dp.class_desc, OBJECT_NAME(dp.major_id);
GO

PRINT '=== Permission setup for api_service complete. ===';
GO
