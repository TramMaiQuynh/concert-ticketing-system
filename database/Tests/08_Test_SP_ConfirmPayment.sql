-- ============================================================
-- 08_Test_SP_ConfirmPayment.sql
-- Test sp_ConfirmPayment (@BookingID, @PaymentID, @ProviderRef).
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'SP_ConfirmPayment';
DECLARE @SQL NVARCHAR(MAX);

-- ===== 52001: BookingID khong ton tai =====
SET @SQL = N'
    EXEC sp_ConfirmPayment @BookingID=999999, @PaymentID=1;';
EXEC sp_RunTest @Suite,'BookingNotExists_Fail52001','ERROR',52001,@SQL;

-- ===== 52002: Booking khong Pending =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Cancelled'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;';
EXEC sp_RunTest @Suite,'BookingNotPending_Fail52002','ERROR',52002,@SQL;

-- ===== 52003: PaymentID khong ton tai hoac sai Booking =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=999999;';
EXEC sp_RunTest @Suite,'PaymentNotExists_Fail52003','ERROR',52003,@SQL;

-- ===== 52004: Payment khong Pending (da Confirmed) =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Confirmed'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;';
EXEC sp_RunTest @Suite,'PaymentAlreadyConfirmed_Fail52004','ERROR',52004,@SQL;

-- ===== 52005: Amount khong khop FinalAmount =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',500000,''REF-TEST'');  -- sai so tien
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;';
EXEC sp_RunTest @Suite,'PaymentAmountMismatch_Fail52005','ERROR',52005,@SQL;

-- ===== Happy Path =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID);
    DECLARE @bid INT, @pid INT;
    -- Tao booking dung SP
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;
    -- Insert payment voi dung FinalAmount
    DECLARE @fa DECIMAL(18,0) = (SELECT FinalAmount FROM Booking WHERE BookingID=@bid);
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentMethod,PaymentReference)
    VALUES (@bid,''Pending'',@fa,''CARD'',''REF-HAPPY-001'');
    SET @pid = SCOPE_IDENTITY();
    -- Confirm
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid, @ProviderReference=''PROVIDER-001'';
    -- Verify
    IF (SELECT BookingStatus FROM Booking WHERE BookingID=@bid) <> ''Confirmed''
        THROW 50000, ''Booking phai Confirmed'', 1;
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid) <> ''Confirmed''
        THROW 50000, ''Payment phai Confirmed'', 1;
    IF (SELECT InventoryStatus FROM EventSeat WHERE EventSeatID=@esid) <> ''Booked''
        THROW 50000, ''EventSeat phai Booked'', 1;
    IF NOT EXISTS (SELECT 1 FROM Ticket WHERE BookingID=@bid AND TicketStatus=''Issued'')
        THROW 50000, ''Ticket chua duoc phat hanh'', 1;';
EXEC sp_RunTest @Suite,'ConfirmPayment_HappyPath','SUCCESS',NULL,@SQL;

PRINT '== SP_ConfirmPayment Tests Done ==';
GO


