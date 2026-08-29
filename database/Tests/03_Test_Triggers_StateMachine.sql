-- ============================================================
-- 03_Test_Triggers_StateMachine.sql
-- Test TRG_*_StateTransition (BR49).
-- Chuyen doi trang thai KHONG hop le -> phai loi.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StateMachine';
DECLARE @SQL NVARCHAR(MAX);

-- Helper: lay ID cua Concert test
DECLARE @ConcertID INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
DECLARE @CustID1   INT = (SELECT UserID FROM UserAccount WHERE Username='test_cust1');

-- ===== Concert State Machine =====
-- Draft -> Completed (SKIP Published/OnSale) -> phai loi
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    UPDATE Concert SET ConcertStatus=''Completed'' WHERE ConcertID=@cid AND ConcertStatus=''OnSale'';';
EXEC sp_RunTest @Suite,'Concert_OnSale_to_Completed_Fail','ERROR',50001,@SQL;

-- OnSale -> Cancelled (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    UPDATE Concert SET ConcertStatus=''Cancelled'' WHERE ConcertID=@cid AND ConcertStatus=''OnSale'';';
EXEC sp_RunTest @Suite,'Concert_OnSale_to_Cancelled_OK','SUCCESS',NULL,@SQL;

-- ===== Booking State Machine =====
-- Confirmed -> Pending (INVALID)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Confirmed'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Pending'' WHERE BookingID=@bid;';
EXEC sp_RunTest @Suite,'Booking_Confirmed_to_Pending_Fail','ERROR',50002,@SQL;

-- Pending -> Confirmed (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'' WHERE BookingID=@bid;';
EXEC sp_RunTest @Suite,'Booking_Pending_to_Confirmed_OK','SUCCESS',NULL,@SQL;

-- Pending -> Expired (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Expired'' WHERE BookingID=@bid;';
EXEC sp_RunTest @Suite,'Booking_Pending_to_Expired_OK','SUCCESS',NULL,@SQL;

-- Expired -> Confirmed (INVALID)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Expired'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'' WHERE BookingID=@bid;';
EXEC sp_RunTest @Suite,'Booking_Expired_to_Confirmed_Fail','ERROR',50002,@SQL;

-- ===== Payment State Machine =====
-- Pending -> Refunded (INVALID, phai qua Confirmed truoc)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Refunded'' WHERE PaymentID=@pid;';
EXEC sp_RunTest @Suite,'Payment_Pending_to_Refunded_Fail','ERROR',50003,@SQL;

-- Pending -> Confirmed (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'' WHERE PaymentID=@pid;';
EXEC sp_RunTest @Suite,'Payment_Pending_to_Confirmed_OK','SUCCESS',NULL,@SQL;

-- ===== Ticket State Machine =====
-- Used -> Issued (INVALID)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT, @tid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Confirmed'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid,''TCK_USED_TEST'',''Used'');
    SET @tid = SCOPE_IDENTITY();
    UPDATE Ticket SET TicketStatus=''Issued'' WHERE TicketID=@tid;';
EXEC sp_RunTest @Suite,'Ticket_Used_to_Issued_Fail','ERROR',50004,@SQL;

-- ===== EventSeat State Machine =====
-- Available -> Booked (INVALID, phai qua OnHold truoc)
SET @SQL = N'
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    UPDATE EventSeat SET InventoryStatus=''Booked'' WHERE EventSeatID=@esid;';
EXEC sp_RunTest @Suite,'EventSeat_Available_to_Booked_Fail','ERROR',50005,@SQL;

-- Available -> OnHold (hop le)
SET @SQL = N'
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;';
EXEC sp_RunTest @Suite,'EventSeat_Available_to_OnHold_OK','SUCCESS',NULL,@SQL;

-- ===== Refund State Machine =====
-- Pending -> Pending (no-op, OK)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Confirmed'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Confirmed'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',500000);
    SET @rid = SCOPE_IDENTITY();
    UPDATE Refund SET RefundStatus=''Pending'' WHERE RefundID=@rid;';
EXEC sp_RunTest @Suite,'Refund_Pending_NoOp_OK','SUCCESS',NULL,@SQL;

PRINT '== StateMachine Tests Done ==';
GO


