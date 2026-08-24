-- ============================================================
-- 11_Test_Concurrency.sql
-- Test chong Oversell: 2 session cung goi sp_CreateBooking
-- cho cung 1 EventSeat -> chi 1 duoc thanh cong.
-- Chay truc tiep trong SQL Server, khong can PowerShell thread.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Concurrency';
DECLARE @SQL NVARCHAR(MAX);

-- ===== Test: 2 Booking cung 1 EventSeat Available -> chi 1 thang =====
-- Muc tieu: Kiem tra co che conditional UPDATE (@@ROWCOUNT check) trong sp_CreateBooking.
-- Chay 2 lan lien tiep:
--   Lan 1: Phai thanh cong (ghe chuyen OnHold)
--   Lan 2: Phai that bai voi 51004 (ghe da OnHold)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid1 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID);
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR);
    
    -- Booking 1 phai thanh cong
    DECLARE @bid1 INT;
    EXEC sp_CreateBooking @CustomerUserID=@uid1, @ConcertID=@cid,
        @SeatList=@seatstr, @NewBookingID=@bid1 OUTPUT;
    IF @bid1 IS NULL THROW 50000, ''Booking1 phai thanh cong'', 1;
    IF (SELECT InventoryStatus FROM EventSeat WHERE EventSeatID=@esid) <> ''OnHold''
        THROW 50000, ''EventSeat phai OnHold sau booking1'', 1;
    
    -- Booking 2 phai that bai voi 51004
    DECLARE @bid2 INT = NULL;
    EXEC sp_CreateBooking @CustomerUserID=@uid2, @ConcertID=@cid,
        @SeatList=@seatstr, @NewBookingID=@bid2 OUTPUT;';
EXEC sp_RunTest @Suite,'OversellGuard_SameSeat_OnlyOneWins','ERROR',51004,@SQL;

-- ===== Test: 2 Booking tren ghe KHAC NHAU -> ca 2 phai thanh cong =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid1 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid1 INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID);
    DECLARE @esid2 INT = (SELECT EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY);
    
    IF @esid2 IS NULL THROW 50000, ''Can it nhat 2 ghe Available'', 1;
    
    DECLARE @bid1 INT, @bid2 INT;
    DECLARE @seatstr1 NVARCHAR(MAX) = CAST(@esid1 AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid1, @ConcertID=@cid, @SeatList=@seatstr1, @NewBookingID=@bid1 OUTPUT;
    DECLARE @seatstr2 NVARCHAR(MAX) = CAST(@esid2 AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid2, @ConcertID=@cid, @SeatList=@seatstr2, @NewBookingID=@bid2 OUTPUT;
    
    IF @bid1 IS NULL OR @bid2 IS NULL
        THROW 50000, ''Ca 2 booking phai thanh cong'', 1;';
EXEC sp_RunTest @Suite,'DifferentSeats_BothSucceed','SUCCESS',NULL,@SQL;

PRINT '== Concurrency Tests Done ==';
GO


