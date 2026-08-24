-- ============================================================
-- 09_Test_SP_Others.sql
-- Test sp_ApplyPromotion, sp_CheckInTicket, sp_ProcessRefund,
--      sp_ReleaseExpiredHolds, sp_AllocateWaitlist.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'SP_Others';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- sp_ApplyPromotion
-- Signature: @BookingID, @PromotionID, @DiscountCodeID=NULL, @ActorUserID
-- ============================================================
-- 54003: PromotionID khong ton tai
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount)
    VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=999999,
         @DiscountCodeID=NULL, @ActorUserID=@uid;';
EXEC sp_RunTest @Suite,'ApplyPromo_PromotionNotFound_Fail54003','ERROR',54003,@SQL;

-- 54004: Promotion khong thuoc Concert cua Booking
SET @SQL = N'
    -- Tao concert 2 va promotion rieng
    DECLARE @vid INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cid2 INT, @pid2 INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
        StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@aid,@vid,''Concert 2'',''OnSale'',DATEADD(d,20,SYSDATETIME()),DATEADD(d,21,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,
        StartDatetime,EndDatetime,UsageLimit,CodeRequiredFlag,PromotionStatus)
    VALUES (@cid2,''Promo2'',''FIXED'',100000,SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),100,0,''Active'');
    SET @pid2 = SCOPE_IDENTITY();
    -- Booking thuoc Concert 1 nhung dung Promotion Concert 2
    DECLARE @cid1 INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount)
    VALUES (@uid,@cid1,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid2,
         @DiscountCodeID=NULL, @ActorUserID=@uid;';
EXEC sp_RunTest @Suite,'ApplyPromo_WrongConcert_Fail54004','ERROR',54004,@SQL;

-- 54008: Promotion yeu cau Code nhung khong truyen Code
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT = (SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid AND CodeRequiredFlag=1);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount)
    VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid,
         @DiscountCodeID=NULL, @ActorUserID=@uid;';
EXEC sp_RunTest @Suite,'ApplyPromo_CodeRequired_NoCode_Fail54008','ERROR',54008,@SQL;

-- 54009: DiscountCode sai / het han
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT = (SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid AND CodeRequiredFlag=1);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount)
    VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid,
         @DiscountCodeID=999999, @ActorUserID=@uid;';
EXEC sp_RunTest @Suite,'ApplyPromo_InvalidCode_Fail54009','ERROR',54009,@SQL;

-- Happy Path sp_ApplyPromotion
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT = (SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @dcid INT = (SELECT TOP 1 DiscountCodeID FROM DiscountCode WHERE PromotionID=@pid AND CodeStatus=''Active'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount)
    VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid,
         @DiscountCodeID=@dcid, @ActorUserID=@uid;
    DECLARE @final DECIMAL(18,0) = (SELECT FinalAmount FROM Booking WHERE BookingID=@bid);
    IF @final >= 1000000 THROW 50000, ''FinalAmount phai giam xuong'', 1;';
EXEC sp_RunTest @Suite,'ApplyPromo_HappyPath','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_CheckInTicket
-- Signature: @TicketCode, @ConcertID, @CheckInStaffUserID, @ValidationResult OUT, @ValidationInfo OUT
-- ============================================================
-- Happy Path: Ticket hop le
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'' AND ConcertID=@cid ORDER BY EventSeatID);
    DECLARE @bid INT;
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;
    DECLARE @fa DECIMAL(18,0) = (SELECT FinalAmount FROM Booking WHERE BookingID=@bid);
    DECLARE @pid INT;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentMethod) VALUES (@bid,''Pending'',@fa,''CARD'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;
    -- Lay ticket code
    DECLARE @tcode VARCHAR(64) = (SELECT TOP 1 TicketCode FROM Ticket WHERE BookingID=@bid);
    DECLARE @vresult VARCHAR(32), @vinfo NVARCHAR(500);
    EXEC sp_CheckInTicket @TicketCode=@tcode, @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vresult OUT, @ValidationInfo=@vinfo OUT;
    IF @vresult <> ''SUCCESS'' BEGIN DECLARE @m5 NVARCHAR(200)=''ValidationResult phai SUCCESS, got: ''+@vresult; THROW 50000, @m5, 1; END;';
EXEC sp_RunTest @Suite,'CheckIn_HappyPath','SUCCESS',NULL,@SQL;

-- Ticket khong ton tai -> INVALID (khong throw, tra ve ValidationResult)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @vresult VARCHAR(32), @vinfo NVARCHAR(500);
    EXEC sp_CheckInTicket @TicketCode=''FAKE_CODE_999'', @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vresult OUT, @ValidationInfo=@vinfo OUT;
    IF @vresult <> ''INVALID'' BEGIN DECLARE @m6 NVARCHAR(200)=''Expected INVALID got: ''+@vresult; THROW 50000, @m6, 1; END;';
EXEC sp_RunTest @Suite,'CheckIn_InvalidTicket_INVALID','SUCCESS',NULL,@SQL;

-- Checkin lan 2 -> DUPLICATE
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'' AND ConcertID=@cid ORDER BY EventSeatID);
    DECLARE @bid INT, @pid INT;
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;
    DECLARE @fa DECIMAL(18,0) = (SELECT FinalAmount FROM Booking WHERE BookingID=@bid);
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentMethod) VALUES (@bid,''Pending'',@fa,''CARD'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;
    DECLARE @tcode VARCHAR(64) = (SELECT TOP 1 TicketCode FROM Ticket WHERE BookingID=@bid);
    DECLARE @vresult VARCHAR(32), @vinfo NVARCHAR(500);
    EXEC sp_CheckInTicket @TicketCode=@tcode, @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vresult OUT, @ValidationInfo=@vinfo OUT;
    -- Lan 2
    EXEC sp_CheckInTicket @TicketCode=@tcode, @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vresult OUT, @ValidationInfo=@vinfo OUT;
    IF @vresult NOT IN (''ALREADY_USED'',''DUPLICATE_CHECKIN'')
        BEGIN DECLARE @m7 NVARCHAR(200)=''Expected ALREADY_USED/DUPLICATE, got: ''+@vresult; THROW 50000, @m7, 1; END;';
EXEC sp_RunTest @Suite,'CheckIn_Duplicate_ALREADYUSED','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_ProcessRefund
-- Signature: @PaymentID, @RefundAmount, @RefundReason, @ActorUserID, @RefundReference, @NewRefundID OUT
-- ============================================================
-- 53002: Payment khong Confirmed
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Confirmed',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''Pending'',1000000);
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ProcessRefund @PaymentID=@pid, @RefundAmount=500000,
         @RefundReason=''Test'', @ActorUserID=@uid, @NewRefundID=@rid OUT;';
EXEC sp_RunTest @Suite,'ProcessRefund_PaymentNotConfirmed_Fail53002','ERROR',53002,@SQL;

-- 53004: Refund vuot qua Payment.Amount
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Confirmed',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''Confirmed'',500000);
    SET @pid = SCOPE_IDENTITY();
    -- Refund 1: 300k ok
    EXEC sp_ProcessRefund @PaymentID=@pid, @RefundAmount=300000,
         @RefundReason=''Partial'', @ActorUserID=@uid, @NewRefundID=@rid OUT;
    -- Refund 2: them 300k -> tong 600k > 500k -> phai loi
    EXEC sp_ProcessRefund @PaymentID=@pid, @RefundAmount=300000,
         @RefundReason=''Exceed'', @ActorUserID=@uid, @NewRefundID=@rid OUT;';
EXEC sp_RunTest @Suite,'ProcessRefund_ExceedAmount_Fail53004','ERROR',53004,@SQL;

-- Happy Path sp_ProcessRefund
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Confirmed',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''Confirmed'',1000000);
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ProcessRefund @PaymentID=@pid, @RefundAmount=500000,
         @RefundReason=''Partial refund'', @ActorUserID=@uid, @NewRefundID=@rid OUT;
    IF @rid IS NULL THROW 50000, ''RefundID is NULL'', 1;
    IF (SELECT RefundAmount FROM Refund WHERE RefundID=@rid) <> 500000
        THROW 50000, ''RefundAmount sai'', 1;';
EXEC sp_RunTest @Suite,'ProcessRefund_HappyPath','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_ReleaseExpiredHolds
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID);
    DECLARE @bid INT;
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;
    -- Dat expiry ve qua khu
    UPDATE Booking SET HoldExpiryDatetime=DATEADD(HOUR,-1,SYSDATETIME())
    WHERE BookingID=@bid;
    -- Chay release
    EXEC sp_ReleaseExpiredHolds;
    -- Verify
    IF (SELECT BookingStatus FROM Booking WHERE BookingID=@bid) <> ''Expired''
        THROW 50000, ''Booking phai Expired'', 1;
    IF (SELECT InventoryStatus FROM EventSeat WHERE EventSeatID=@esid) <> ''Available''
        THROW 50000, ''EventSeat phai Available sau release'', 1;';
EXEC sp_RunTest @Suite,'ReleaseExpiredHolds_HappyPath','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_AllocateWaitlist
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    EXEC sp_AllocateWaitlist @ConcertID=@cid;';
EXEC sp_RunTest @Suite,'AllocateWaitlist_Runs','SUCCESS',NULL,@SQL;

PRINT '== SP_Others Tests Done ==';
GO


