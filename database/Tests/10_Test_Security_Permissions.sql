-- ============================================================
-- 10_Test_Security_Permissions.sql
-- Test RBAC permissions theo GrantPermissions.sql thực tế.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Security_RBAC';
DECLARE @SQL NVARCHAR(MAX);

-- ===== app_customer: DENY SELECT on Booking =====
SET @SQL = N'
    EXECUTE AS USER = ''app_customer'';
    BEGIN TRY
        DECLARE @n INT = (SELECT COUNT(*) FROM Booking);
        REVERT;
        THROW 50000, ''Expected DENY on Booking but SELECT succeeded'', 1;
    END TRY
    BEGIN CATCH
        REVERT;
        IF ERROR_NUMBER() = 50000 THROW;  -- re-throw test fail
        -- loi 229 = SELECT denied -> dat yeu cau
    END CATCH;';
EXEC sp_RunTest @Suite,'Customer_DENY_SELECT_Booking','SUCCESS',NULL,@SQL;

-- ===== app_customer: DENY SELECT on Payment =====
SET @SQL = N'
    EXECUTE AS USER = ''app_customer'';
    BEGIN TRY
        DECLARE @n INT = (SELECT COUNT(*) FROM Payment);
        REVERT;
        THROW 50000, ''Expected DENY on Payment'', 1;
    END TRY
    BEGIN CATCH
        REVERT;
        IF ERROR_NUMBER() = 50000 THROW;
    END CATCH;';
EXEC sp_RunTest @Suite,'Customer_DENY_SELECT_Payment','SUCCESS',NULL,@SQL;

-- ===== app_customer: GRANT SELECT on VW_CustomerBookingHistory =====
SET @SQL = N'
    EXECUTE AS USER = ''app_customer'';
    BEGIN TRY
        DECLARE @n INT = (SELECT COUNT(*) FROM VW_CustomerBookingHistory);
        REVERT;
    END TRY
    BEGIN CATCH
        REVERT;
        THROW;
    END CATCH;';
EXEC sp_RunTest @Suite,'Customer_GRANT_SELECT_View','SUCCESS',NULL,@SQL;

-- ===== app_organizer: DENY SELECT on AuditRecord =====
SET @SQL = N'
    EXECUTE AS USER = ''app_organizer'';
    BEGIN TRY
        DECLARE @n INT = (SELECT COUNT(*) FROM AuditRecord);
        REVERT;
        THROW 50000, ''Expected DENY on AuditRecord'', 1;
    END TRY
    BEGIN CATCH
        REVERT;
        IF ERROR_NUMBER() = 50000 THROW;
    END CATCH;';
EXEC sp_RunTest @Suite,'Organizer_DENY_SELECT_AuditRecord','SUCCESS',NULL,@SQL;

-- ===== app_organizer: GRANT SELECT on Booking (xem don hang) =====
SET @SQL = N'
    EXECUTE AS USER = ''app_organizer'';
    BEGIN TRY
        DECLARE @n INT = (SELECT COUNT(*) FROM Booking);
        REVERT;
    END TRY
    BEGIN CATCH
        REVERT;
        THROW;
    END CATCH;';
EXEC sp_RunTest @Suite,'Organizer_GRANT_SELECT_Booking','SUCCESS',NULL,@SQL;

-- ===== app_checkinstaff: DENY UPDATE on Ticket truc tiep =====
SET @SQL = N'
    EXECUTE AS USER = ''app_checkinstaff'';
    BEGIN TRY
        UPDATE Ticket SET TicketStatus=''Used'' WHERE 1=0;
        REVERT;
        THROW 50000, ''Expected DENY UPDATE on Ticket'', 1;
    END TRY
    BEGIN CATCH
        REVERT;
        IF ERROR_NUMBER() = 50000 THROW;
    END CATCH;';
EXEC sp_RunTest @Suite,'Staff_DENY_UPDATE_Ticket','SUCCESS',NULL,@SQL;

-- ===== app_checkinstaff: DENY SELECT on Payment =====
SET @SQL = N'
    EXECUTE AS USER = ''app_checkinstaff'';
    BEGIN TRY
        DECLARE @n INT = (SELECT COUNT(*) FROM Payment);
        REVERT;
        THROW 50000, ''Expected DENY on Payment'', 1;
    END TRY
    BEGIN CATCH
        REVERT;
        IF ERROR_NUMBER() = 50000 THROW;
    END CATCH;';
EXEC sp_RunTest @Suite,'Staff_DENY_SELECT_Payment','SUCCESS',NULL,@SQL;

-- ===== app_checkinstaff: GRANT SELECT on Ticket =====
SET @SQL = N'
    EXECUTE AS USER = ''app_checkinstaff'';
    BEGIN TRY
        DECLARE @n INT = (SELECT COUNT(*) FROM Ticket);
        REVERT;
    END TRY
    BEGIN CATCH
        REVERT;
        THROW;
    END CATCH;';
EXEC sp_RunTest @Suite,'Staff_GRANT_SELECT_Ticket','SUCCESS',NULL,@SQL;

PRINT '== Security_RBAC Tests Done ==';
GO


