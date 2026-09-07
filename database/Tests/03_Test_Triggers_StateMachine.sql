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
EXEC test.sp_RunTest @Suite,'Concert_OnSale_to_Completed_Fail','ERROR',50001,@SQL;

-- OnSale -> Cancelled (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    UPDATE Concert SET ConcertStatus=''Cancelled'' WHERE ConcertID=@cid AND ConcertStatus=''OnSale'';';
EXEC test.sp_RunTest @Suite,'Concert_OnSale_to_Cancelled_OK','SUCCESS',NULL,@SQL;

-- ===== Booking State Machine =====
-- Confirmed -> Pending (INVALID)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    -- Xoa luon ConfirmedTimestamp: neu khong, CHK_Booking_TimestampCoherence se
    -- chan truoc (547) va test khong cham toi duoc state machine can kiem.
    UPDATE Booking SET BookingStatus=''Pending'', ConfirmedTimestamp=NULL, HoldStartDatetime=SYSDATETIME(), HoldExpiryDatetime=DATEADD(minute, 15, SYSDATETIME()) WHERE BookingID=@bid;';
EXEC test.sp_RunTest @Suite,'Booking_Confirmed_to_Pending_Fail','ERROR',50002,@SQL;

-- Pending -> Confirmed (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@bid;';
EXEC test.sp_RunTest @Suite,'Booking_Pending_to_Confirmed_OK','SUCCESS',NULL,@SQL;

-- Pending -> Expired (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Expired'', ExpiredTimestamp=SYSDATETIME() WHERE BookingID=@bid;';
EXEC test.sp_RunTest @Suite,'Booking_Pending_to_Expired_OK','SUCCESS',NULL,@SQL;

-- Expired -> Confirmed (INVALID)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Expired'', ExpiredTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@bid;';
EXEC test.sp_RunTest @Suite,'Booking_Expired_to_Confirmed_Fail','ERROR',50002,@SQL;

-- ===== Payment State Machine =====
-- Pending -> Refunded (INVALID, phai qua Confirmed truoc)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Refunded'' WHERE PaymentID=@pid;';
EXEC test.sp_RunTest @Suite,'Payment_Pending_to_Refunded_Fail','ERROR',50003,@SQL;

-- Pending -> Confirmed (hop le)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'' WHERE PaymentID=@pid;';
EXEC test.sp_RunTest @Suite,'Payment_Pending_to_Confirmed_OK','SUCCESS',NULL,@SQL;

-- ===== Ticket State Machine =====
-- Used -> Issued (INVALID)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT, @tid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid,@esid,''Active'',1000000);
    -- Ve phai duoc phat hanh o trang thai Issued roi moi chuyen Used: chen thang
    -- ''Used'' vua vi pham trang thai khoi tao (TRG_Ticket_StateTransition) vua vi pham
    -- CHK_Ticket_TimestampCoherence, nen se khong cham toi duoc chuyen doi can kiem.
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid,''TCK_USED_TEST'',''Issued'');
    SET @tid = SCOPE_IDENTITY();
    UPDATE Ticket SET TicketStatus=''Used'', UsedTimestamp=SYSDATETIME() WHERE TicketID=@tid;
    UPDATE Ticket SET TicketStatus=''Issued'', UsedTimestamp=NULL WHERE TicketID=@tid;';
EXEC test.sp_RunTest @Suite,'Ticket_Used_to_Issued_Fail','ERROR',50004,@SQL;

-- ===== EventSeat State Machine =====
-- Available -> Booked (INVALID, phai qua OnHold truoc)
SET @SQL = N'
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    UPDATE EventSeat SET InventoryStatus=''Booked'' WHERE EventSeatID=@esid;';
-- §10.1 (Trang thai EventSeat): Available -> OnHold, OnHoldForWaitlist, Unavailable.
-- KHONG co Available -> Booked. Mot ghe chi tro thanh da ban sau khi da duoc GIU CHO,
-- vi chinh buoc giu cho (conditional update Available -> OnHold) la co che chong ban
-- trung cua BR15a. Ban truoc cua bai nay ky vong SUCCESS - tuc no ghi lai dung hanh vi
-- SAI va lam no trong nhu da duoc kiem, trong khi ten bai da noi ro phai that bai.
EXEC test.sp_RunTest @Suite,'EventSeat_Available_to_Booked_Fail','ERROR',50005,@SQL;

-- Chieu con lai cua cung lo hong: ghe dang giu cho waitlist cung khong duoc nhay thang
-- sang Booked. §10.1: OnHoldForWaitlist -> Available, OnHoldForWaitlist khac, OnHold.
-- Khach waitlist phai tao Booking (ghe chuyen sang OnHold, nhan Temporary Hold moi theo
-- BR53) roi thanh toan thi ghe moi thanh Booked.
SET @SQL = N'
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    UPDATE EventSeat SET InventoryStatus=''OnHoldForWaitlist'' WHERE EventSeatID=@esid;
    UPDATE EventSeat SET InventoryStatus=''Booked'' WHERE EventSeatID=@esid;';
EXEC test.sp_RunTest @Suite,'EventSeat_OnHoldForWaitlist_to_Booked_Fail','ERROR',50005,@SQL;

-- Doi chung duong cho ca hai bai tren: duong hop le OnHold -> Booked phai chay lot.
-- Thieu bai nay thi mot trigger "chan tat ca" cung se lam hai bai tren PASS.
SET @SQL = N'
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    UPDATE EventSeat SET InventoryStatus=''Booked'' WHERE EventSeatID=@esid;';
EXEC test.sp_RunTest @Suite,'EventSeat_OnHold_to_Booked_OK','SUCCESS',NULL,@SQL;

-- Available -> OnHold (hop le)
SET @SQL = N'
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;';
EXEC test.sp_RunTest @Suite,'EventSeat_Available_to_OnHold_OK','SUCCESS',NULL,@SQL;

-- ===== WaitlistEntry State Machine =====
-- Truoc day muc nay KHONG ton tai: state machine cua WaitlistEntry chua he co bai kiem
-- nao, va do la ly do chuyen doi thua Active -> Expired ton tai lau ma khong ai thay.

-- §10.1: Active -> Granted, Cancelled. KHONG co Active -> Expired: 'Expired' nghia la
-- co hoi da het han (BR44), ma Entry con Active thi chua duoc cap co hoi nao.
SET @SQL = N'
    DECLARE @wid INT = (SELECT TOP 1 WaitlistID FROM Waitlist ORDER BY WaitlistID);
    DECLARE @cid INT = (SELECT ConcertID FROM Waitlist WHERE WaitlistID=@wid);
    DECLARE @cat INT = (SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @we INT;
    INSERT INTO WaitlistEntry (WaitlistID,TicketCategoryID,CustomerUserID,RequestedQuantity,EntryStatus)
    VALUES (@wid,@cat,@uid,1,''Active'');
    SET @we = SCOPE_IDENTITY();
    UPDATE WaitlistEntry SET EntryStatus=''Expired'' WHERE WaitlistEntryID=@we;';
EXEC test.sp_RunTest @Suite,'WaitlistEntry_Active_to_Expired_Fail','ERROR',50007,@SQL;

-- Doi chung duong: Active -> Granted phai chay lot, neu khong bai tren la vo nghia.
SET @SQL = N'
    DECLARE @wid INT = (SELECT TOP 1 WaitlistID FROM Waitlist ORDER BY WaitlistID);
    DECLARE @cid INT = (SELECT ConcertID FROM Waitlist WHERE WaitlistID=@wid);
    DECLARE @cat INT = (SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @we INT;
    INSERT INTO WaitlistEntry (WaitlistID,TicketCategoryID,CustomerUserID,RequestedQuantity,EntryStatus)
    VALUES (@wid,@cat,@uid,1,''Active'');
    SET @we = SCOPE_IDENTITY();
    UPDATE WaitlistEntry SET EntryStatus=''Granted'', OpportunityGrantedTimestamp=SYSDATETIME(),
           OpportunityExpiryTimestamp=DATEADD(minute,15,SYSDATETIME()) WHERE WaitlistEntryID=@we;
    IF NOT EXISTS (SELECT 1 FROM WaitlistEntry WHERE WaitlistEntryID=@we AND EntryStatus=''Granted'')
        THROW 59998, ''Active -> Granted bi chan oan.'', 1;';
EXEC test.sp_RunTest @Suite,'WaitlistEntry_Active_to_Granted_OK','SUCCESS',NULL,@SQL;

-- Granted -> Expired VAN phai hop le: do moi la duong that ma sp_ReleaseExpiredHolds di.
SET @SQL = N'
    DECLARE @wid INT = (SELECT TOP 1 WaitlistID FROM Waitlist ORDER BY WaitlistID);
    DECLARE @cid INT = (SELECT ConcertID FROM Waitlist WHERE WaitlistID=@wid);
    DECLARE @cat INT = (SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @we INT;
    INSERT INTO WaitlistEntry (WaitlistID,TicketCategoryID,CustomerUserID,RequestedQuantity,EntryStatus)
    VALUES (@wid,@cat,@uid,1,''Active'');
    SET @we = SCOPE_IDENTITY();
    UPDATE WaitlistEntry SET EntryStatus=''Granted'', OpportunityGrantedTimestamp=SYSDATETIME(),
           OpportunityExpiryTimestamp=DATEADD(minute,15,SYSDATETIME()) WHERE WaitlistEntryID=@we;
    UPDATE WaitlistEntry SET EntryStatus=''Expired'' WHERE WaitlistEntryID=@we;
    IF NOT EXISTS (SELECT 1 FROM WaitlistEntry WHERE WaitlistEntryID=@we AND EntryStatus=''Expired'')
        THROW 59998, ''Granted -> Expired bi chan oan.'', 1;';
EXEC test.sp_RunTest @Suite,'WaitlistEntry_Granted_to_Expired_OK','SUCCESS',NULL,@SQL;

-- ===== Refund State Machine =====
-- Pending -> Pending (no-op, OK)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
      UPDATE Payment SET PaymentStatus=''Confirmed'' WHERE PaymentID = SCOPE_IDENTITY();
    SET @pid = SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',500000);
    SET @rid = SCOPE_IDENTITY();
    UPDATE Refund SET RefundStatus=''Pending'' WHERE RefundID=@rid;';
EXEC test.sp_RunTest @Suite,'Refund_Pending_NoOp_OK','SUCCESS',NULL,@SQL;

PRINT '== StateMachine Tests Done ==';
GO


