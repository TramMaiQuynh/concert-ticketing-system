-- ============================================================
-- 06_Test_Views.sql
-- Test 6 Views: khong loi khi chay, tra ve ket qua.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Views';
DECLARE @SQL NVARCHAR(MAX);

SET @SQL = N'DECLARE @n INT = (SELECT COUNT(*) FROM VW_ConcertSalesSummary);';
EXEC sp_RunTest @Suite,'VW_ConcertSalesSummary_Runs','SUCCESS',NULL,@SQL;

SET @SQL = N'DECLARE @n INT = (SELECT COUNT(*) FROM VW_ActiveInventoryStatus);';
EXEC sp_RunTest @Suite,'VW_ActiveInventoryStatus_Runs','SUCCESS',NULL,@SQL;

SET @SQL = N'DECLARE @n INT = (SELECT COUNT(*) FROM VW_CustomerBookingHistory);';
EXEC sp_RunTest @Suite,'VW_CustomerBookingHistory_Runs','SUCCESS',NULL,@SQL;

SET @SQL = N'DECLARE @n INT = (SELECT COUNT(*) FROM VW_CheckInReport);';
EXEC sp_RunTest @Suite,'VW_CheckInReport_Runs','SUCCESS',NULL,@SQL;

SET @SQL = N'DECLARE @n INT = (SELECT COUNT(*) FROM VW_WaitlistQueue);';
EXEC sp_RunTest @Suite,'VW_WaitlistQueue_Runs','SUCCESS',NULL,@SQL;

SET @SQL = N'DECLARE @n INT = (SELECT COUNT(*) FROM VW_AuditTrail);';
EXEC sp_RunTest @Suite,'VW_AuditTrail_Runs','SUCCESS',NULL,@SQL;

PRINT '== Views Tests Done ==';
GO


