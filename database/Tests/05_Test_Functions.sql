-- ============================================================
-- 05_Test_Functions.sql
-- Test 3 scalar functions.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Functions';
DECLARE @SQL NVARCHAR(MAX);

-- ===== fn_GetCustomerTicketCount =====
-- Customer chua co booking -> count = 0
SET @SQL = N'
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @cnt INT = (SELECT TicketCount FROM dbo.fn_GetCustomerTicketCount(@uid, 999999));
    IF @cnt <> 0 THROW 50000, ''Expected 0'', 1;';
EXEC sp_RunTest @Suite,'fn_GetCustomerTicketCount_NoBooking','SUCCESS',NULL,@SQL;

-- Customer co 2 Active allocation Pending -> count = 2
SET @SQL = N'
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @esid1 INT = (SELECT MIN(EventSeatID) FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @esid2 INT = (SELECT MIN(EventSeatID) FROM EventSeat WHERE InventoryStatus=''Available'' AND EventSeatID > @esid1);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    -- Ghe phai OnHold truoc moi insert Active Allocation
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID IN (@esid1,@esid2);
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid1,''Active'',1000000), (@bid,@esid2,''Active'',1000000);
    DECLARE @cnt INT = (SELECT TicketCount FROM dbo.fn_GetCustomerTicketCount(@uid,@cid));
    IF @cnt <> 2 BEGIN DECLARE @m1 NVARCHAR(200)=''Expected count=2, got ''+CAST(@cnt AS VARCHAR); THROW 50000, @m1, 1; END;';
EXEC sp_RunTest @Suite,'fn_GetCustomerTicketCount_With2Pending','SUCCESS',NULL,@SQL;

-- ===== fn_CalculateBookingSubtotal =====
-- Subtotal = sum PriceSnapshot cua Active allocations (khong tinh Released)
SET @SQL = N'
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @esid1 INT = (SELECT MIN(EventSeatID) FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @esid2 INT = (SELECT MIN(EventSeatID) FROM EventSeat WHERE InventoryStatus=''Available'' AND EventSeatID > @esid1);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID IN (@esid1,@esid2);
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid1,''Active'',1000000), (@bid,@esid2,''Released'',500000);
    DECLARE @sub DECIMAL(18,0) = (SELECT Subtotal FROM dbo.fn_CalculateBookingSubtotal(@bid));
    IF @sub <> 1000000 BEGIN DECLARE @m2 NVARCHAR(200)=''Expected subtotal=1000000, got ''+CAST(@sub AS VARCHAR); THROW 50000, @m2, 1; END;';
EXEC sp_RunTest @Suite,'fn_CalculateBookingSubtotal_OnlyActive','SUCCESS',NULL,@SQL;

-- ===== fn_CalculateFinalAmount =====
-- Final = Subtotal - discount, khong am
SET @SQL = N'
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,StartDatetime,EndDatetime,PromotionStatus,CodeRequiredFlag)
    VALUES (@cid, ''TestPromo'', ''Fixed'', 200000, SYSDATETIME(), DATEADD(day, 1, SYSDATETIME()), ''Active'', 0);
    DECLARE @pid INT = SCOPE_IDENTITY();
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'' ORDER BY EventSeatID);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount)
    VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid,''Active'',1000000);
    INSERT INTO BookingPromotionApplication (BookingID,PromotionID,DiscountAmount,AppliedTimestamp)
    VALUES (@bid,@pid,200000,SYSDATETIME());
    DECLARE @final DECIMAL(18,0) = (SELECT FinalAmount FROM dbo.fn_CalculateFinalAmount(@bid));
    IF @final <> 800000 BEGIN DECLARE @m3 NVARCHAR(200)=''Expected 800000, got ''+CAST(@final AS VARCHAR); THROW 50000, @m3, 1; END;';
EXEC sp_RunTest @Suite,'fn_CalculateFinalAmount_Fixed200k','SUCCESS',NULL,@SQL;

-- Final khong am (discount lon hon subtotal -> 0)
SET @SQL = N'
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,StartDatetime,EndDatetime,PromotionStatus,CodeRequiredFlag) VALUES (@cid, ''TestPromo'', ''Fixed'', 200000, SYSDATETIME(), DATEADD(day, 1, SYSDATETIME()), ''Active'', 0); DECLARE @pid INT = SCOPE_IDENTITY();
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'' ORDER BY EventSeatID);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount)
    VALUES (@uid,@cid,''Pending'',100000,100000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid,''Active'',100000);
    INSERT INTO BookingPromotionApplication (BookingID,PromotionID,DiscountAmount,AppliedTimestamp)
    VALUES (@bid,@pid,500000,SYSDATETIME());  -- Discount > Subtotal
    DECLARE @final DECIMAL(18,0) = (SELECT FinalAmount FROM dbo.fn_CalculateFinalAmount(@bid));
    IF @final <> 0 BEGIN DECLARE @m4 NVARCHAR(200)=''Expected 0, got ''+CAST(@final AS VARCHAR); THROW 50000, @m4, 1; END;';
EXEC sp_RunTest @Suite,'fn_CalculateFinalAmount_ZeroFloor','SUCCESS',NULL,@SQL;

PRINT '== Functions Tests Done ==';
GO


