-- ============================================================
-- 02_Test_Tables_Constraints.sql
-- Test CHECK constraints va UNIQUE indexes.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Constraints';
DECLARE @SQL NVARCHAR(MAX);

-- ===== Concert =====
-- CHK_Concert_Status: trang thai khong hop le
SET @SQL = N'
    DECLARE @vid INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
        StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@uid,@aid,@vid,''Bad'',''INVALID_STATUS'',
        DATEADD(d,1,SYSDATETIME()),DATEADD(d,2,SYSDATETIME()),4,0,0,0);';
EXEC sp_RunTest @Suite,'CHK_Concert_Status_Invalid','ERROR',NULL,@SQL;

-- CHK_Concert_Dates: EndDatetime <= StartDatetime
SET @SQL = N'
    DECLARE @vid INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
        StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@uid,@aid,@vid,''Bad Dates'',''Draft'',
        DATEADD(d,2,SYSDATETIME()),DATEADD(d,1,SYSDATETIME()),4,0,0,0);';
EXEC sp_RunTest @Suite,'CHK_Concert_Dates_Invalid','ERROR',NULL,@SQL;

-- ===== EventSeat =====
-- CHK_EventSeat_Status: trang thai sai
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @sid INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @tid INT = (SELECT TOP 1 TicketCategoryID FROM TicketCategory);
    INSERT INTO EventSeat (ConcertID,SeatID,TicketCategoryID,InventoryStatus,SalePrice)
    VALUES (@cid,@sid,@tid,''WRONG_STATUS'',100000);';
EXEC sp_RunTest @Suite,'CHK_EventSeat_Status_Invalid','ERROR',NULL,@SQL;

-- ===== DiscountCode =====
-- CHK_DiscountCode_Status: trang thai sai
SET @SQL = N'
    DECLARE @pid INT = (SELECT TOP 1 PromotionID FROM Promotion);
    INSERT INTO DiscountCode (PromotionID,CodeValue,CodeStatus)
    VALUES (@pid,''BADCODE'',''Disabled'');';
EXEC sp_RunTest @Suite,'CHK_DiscountCode_Status_Invalid','ERROR',NULL,@SQL;

-- ===== Payment =====
-- CHK_Payment_Amount: Amount <= 0
SET @SQL = N'
    DECLARE @bid INT;
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Pending',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''Pending'',-100);';
EXEC sp_RunTest @Suite,'CHK_Payment_Amount_Negative','ERROR',NULL,@SQL;

-- CHK_Payment_Status: trang thai sai
SET @SQL = N'
    DECLARE @bid INT;
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Pending',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''BadStatus'',100000);';
EXEC sp_RunTest @Suite,'CHK_Payment_Status_Invalid','ERROR',NULL,@SQL;

-- ===== Ticket =====
-- CHK_Ticket_Timestamps: khong duoc co ca 2 UsedTimestamp va CancelledTimestamp
SET @SQL = N'
    DECLARE @bid INT;
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Confirmed',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus,UsedTimestamp,CancelledTimestamp)
    VALUES (@bid,@esid,@cid,''TCK_BOTH'',''Issued'',SYSDATETIME(),SYSDATETIME());';
EXEC sp_RunTest @Suite,'CHK_Ticket_Timestamps_BothSet','ERROR',NULL,@SQL;

-- ===== UIX_Allocation_ActiveEventSeat =====
-- 2 Active allocation tren cung 1 EventSeat -> phai loi
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @uid1 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid1 INT, @bid2 INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid1,@cid,'Pending',1000000,1000000);
    SET @bid1=SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid2,@cid,'Pending',1000000,1000000);
    SET @bid2=SCOPE_IDENTITY();
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus)
    VALUES (@bid1,@esid,''Active'');
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus)
    VALUES (@bid2,@esid,''Active'');';
EXEC sp_RunTest @Suite,'UIX_Allocation_2Active_SameSeat','ERROR',NULL,@SQL;

-- 1 Active + 1 Released tren cung ghe -> OK
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @uid1 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid1 INT, @bid2 INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid1,@cid,'Pending',1000000,1000000);
    SET @bid1=SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid2,@cid,'Pending',1000000,1000000);
    SET @bid2=SCOPE_IDENTITY();
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus)
    VALUES (@bid1,@esid,''Released'');
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus)
    VALUES (@bid2,@esid,''Active'');';
EXEC sp_RunTest @Suite,'UIX_Allocation_1Active_1Released_OK','SUCCESS',NULL,@SQL;

PRINT '== Constraints Tests Done ==';
GO


