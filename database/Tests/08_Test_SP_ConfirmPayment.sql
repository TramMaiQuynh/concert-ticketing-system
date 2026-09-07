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
EXEC test.sp_RunTest @Suite,'BookingNotExists_Fail52001','ERROR',52001,@SQL;

-- ===== Booking khong con Pending: KHONG nem loi, tu tao Refund 100% =====
-- BR22a/LI02a va §23.5 buoc sp_ConfirmPayment phai ghi nhan tien da thu roi tu tao
-- Refund, TUYET DOI khong ROLLBACK bo ban ghi do. Vi vay ky vong dung la SUCCESS.
-- Ten cu 'BookingNotPending_Fail52002' la tan du tu thiet ke cu (khi SP con nem 52002)
-- va noi nguoc voi hanh vi that - dung loai nham lan da tung che giau mot lo hong.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Cancelled'', CancelledTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;';
EXEC test.sp_RunTest @Suite,'BookingNotPending_AutoRefunds_OK','SUCCESS',NULL,@SQL;

-- ===== 52003: PaymentID khong ton tai hoac sai Booking =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=999999;';
EXEC test.sp_RunTest @Suite,'PaymentNotExists_Fail52003','ERROR',52001,@SQL;

-- ===== Goi lai tren Payment da Confirmed: idempotent, khong loi =====
-- BR49a: cong thanh toan gui lai callback la chuyen binh thuong; goi lai khong duoc
-- coi la loi. Ten cu 'PaymentAlreadyConfirmed_Fail52004' noi nguoc voi dieu do.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
      UPDATE Payment SET PaymentStatus=''Confirmed'' WHERE PaymentID = SCOPE_IDENTITY();
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;';
EXEC test.sp_RunTest @Suite,'PaymentAlreadyConfirmed_Idempotent_OK','SUCCESS',NULL,@SQL;

-- ===== Amount khong khop FinalAmount -> HOAN TIEN, khong ROLLBACK =====
-- Truoc day nhanh nay nem 52005 va ROLLBACK toan bo, vut bo ca ban ghi "tien da thu".
-- Hanh vi dung: giu PaymentStatus='Confirmed' (su that tai chinh), KHONG gianh quyen
-- hieu luc, tao Refund 100% dang Pending, va de Booking o nguyen Pending de khach con
-- co the tra lai dung so tien.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',500000,''REF-TEST'');  -- sai so tien
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;

    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid) <> ''Confirmed''
        THROW 50000,''Su that tai chinh phai duoc giu: PaymentStatus = Confirmed'',1;
    IF (SELECT IsBookingConfirmingPayment FROM Payment WHERE PaymentID=@pid) <> 0
        THROW 50000,''Payment lech tien khong duoc gianh quyen hieu luc cua Booking'',1;
    IF NOT EXISTS (SELECT 1 FROM Refund WHERE PaymentID=@pid AND RefundStatus=''Pending'' AND RefundAmount=500000)
        THROW 50000,''Phai tao Refund 100% dang Pending cho khoan tien lech'',1;
    IF (SELECT BookingStatus FROM Booking WHERE BookingID=@bid) <> ''Pending''
        THROW 50000,''Booking phai o nguyen Pending de khach tra lai dung so tien'',1;
    IF EXISTS (SELECT 1 FROM Ticket WHERE BookingID=@bid)
        THROW 50000,''Khong duoc phat hanh ve khi so tien khong khop'',1;';
EXEC test.sp_RunTest @Suite,'PaymentAmountMismatch_AutoRefunds','SUCCESS',NULL,@SQL;

-- Sau khi hoan tien, Booking van con Pending nen khach khoi tao lai duoc va tra dung
-- so tien thi don hang hoan tat binh thuong.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'');
    DECLARE @bid INT, @pid1 INT, @pid2 INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
    SET @bid = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid,''Active'',1000000);

    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',500000,''REF-WRONG'');
    SET @pid1 = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid1;

    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-RIGHT'');
    SET @pid2 = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid2;

    IF (SELECT BookingStatus FROM Booking WHERE BookingID=@bid) <> ''Confirmed''
        THROW 50000,''Lan thanh toan dung so tien phai hoan tat duoc don hang'',1;
    IF (SELECT IsBookingConfirmingPayment FROM Payment WHERE PaymentID=@pid2) <> 1
        THROW 50000,''Payment dung so tien phai tro thanh Payment hieu luc'',1;';
EXEC test.sp_RunTest @Suite,'PaymentAmountMismatch_ThenCorrectAmount_Succeeds','SUCCESS',NULL,@SQL;

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
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference)
    VALUES (@bid,''Pending'',@fa,''REF-HAPPY-001'');
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
EXEC test.sp_RunTest @Suite,'ConfirmPayment_HappyPath','SUCCESS',NULL,@SQL;

PRINT '== SP_ConfirmPayment Tests Done ==';
GO


