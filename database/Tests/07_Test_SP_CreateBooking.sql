-- ============================================================
-- 07_Test_SP_CreateBooking.sql
-- Test sp_CreateBooking (@SeatList = NVARCHAR(MAX) csv).
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'SP_CreateBooking';
DECLARE @SQL NVARCHAR(MAX);

-- ===== 51001: Concert khong OnSale =====
SET @SQL = N'
    DECLARE @vid INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cid_draft INT, @bid INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
        StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@uid,@aid,@vid,''Draft Concert'',''Draft'',
        DATEADD(d,10,SYSDATETIME()),DATEADD(d,11,SYSDATETIME()),4,0,0,0);
    SET @cid_draft = SCOPE_IDENTITY();
    EXEC sp_CreateBooking
        @CustomerUserID = @uid,
        @ConcertID      = @cid_draft,
        @SeatList       = ''1'',
        @NewBookingID   = @bid OUTPUT;';
EXEC sp_RunTest @Suite,'Concert_NotOnSale_Fail51001','ERROR',51001,@SQL;

-- ===== 51001: Concert SalesPaused =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    UPDATE Concert SET SalesPaused=1 WHERE ConcertID=@cid;
    EXEC sp_CreateBooking
        @CustomerUserID = @uid,
        @ConcertID      = @cid,
        @SeatList       = ''1'',
        @NewBookingID   = @bid OUTPUT;';
EXEC sp_RunTest @Suite,'Concert_SalesPaused_Fail51001','ERROR',51001,@SQL;

-- ===== 51002: SeatList rong =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    EXEC sp_CreateBooking
        @CustomerUserID = @uid,
        @ConcertID      = @cid,
        @SeatList       = '''',
        @NewBookingID   = @bid OUTPUT;';
EXEC sp_RunTest @Suite,'EmptySeatList_Fail51002','ERROR',51002,@SQL;

-- ===== 51003: Exceed PurchaseLimit =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    -- Concert PurchaseLimit = 4, goi 5 ghe -> phai loi
    DECLARE @seats NVARCHAR(MAX) =
        STUFF((SELECT TOP 5 '',''+CAST(EventSeatID AS VARCHAR)
               FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available''
               ORDER BY EventSeatID FOR XML PATH('''')),1,1,'''');
    EXEC sp_CreateBooking
        @CustomerUserID = @uid,
        @ConcertID      = @cid,
        @SeatList       = @seats,
        @NewBookingID   = @bid OUTPUT;';
EXEC sp_RunTest @Suite,'ExceedPurchaseLimit_Fail51003','ERROR',51003,@SQL;

-- ===== 51004: Seat khong Available =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID);
    -- Dat seat thanh OnHold truoc
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    DECLARE @bid INT;
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;';
EXEC sp_RunTest @Suite,'SeatNotAvailable_Fail51004','ERROR',51004,@SQL;

-- ===== Happy Path: 1 ghe =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID);
    DECLARE @bid INT;
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;
    IF @bid IS NULL THROW 50000, ''BookingID is NULL'', 1;
    IF (SELECT BookingStatus FROM Booking WHERE BookingID=@bid) <> ''Pending''
        THROW 50000, ''Booking phai Pending'', 1;
    IF (SELECT InventoryStatus FROM EventSeat WHERE EventSeatID=@esid) <> ''OnHold''
        THROW 50000, ''EventSeat phai OnHold'', 1;
    IF NOT EXISTS (SELECT 1 FROM BookingEventSeatAllocation WHERE BookingID=@bid AND EventSeatID=@esid AND AllocationStatus=''Active'')
        THROW 50000, ''Allocation khong ton tai'', 1;';
EXEC sp_RunTest @Suite,'CreateBooking_1Seat_HappyPath','SUCCESS',NULL,@SQL;

-- ===== Happy Path: 2 ghe =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid1 INT, @esid2 INT, @bid INT;
    SELECT TOP 1 @esid1 = EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID;
    SELECT @esid2 = EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID OFFSET 1 ROWS FETCH NEXT 1 ROWS ONLY;
    DECLARE @seats NVARCHAR(MAX) = CAST(@esid1 AS VARCHAR)+N'',''+CAST(@esid2 AS VARCHAR);
    EXEC sp_CreateBooking
        @CustomerUserID = @uid,
        @ConcertID      = @cid,
        @SeatList       = @seats,
        @NewBookingID   = @bid OUTPUT;
    DECLARE @cnt INT = (SELECT COUNT(*) FROM BookingEventSeatAllocation WHERE BookingID=@bid AND AllocationStatus=''Active'');
    IF @cnt <> 2 THROW 50000, ''Expected 2 allocations'', 1;';
EXEC sp_RunTest @Suite,'CreateBooking_2Seats_HappyPath','SUCCESS',NULL,@SQL;

PRINT '== SP_CreateBooking Tests Done ==';
GO


