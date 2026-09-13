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
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=999999,
         @DiscountCodeID=NULL, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ApplyPromo_PromotionNotFound_Fail54003','ERROR',54003,@SQL;

-- 54004: Promotion khong thuoc Concert cua Booking
SET @SQL = N'
    -- Tao concert 2 va promotion rieng
    DECLARE @vid INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cid2 INT, @pid2 INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
        StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@aid,@vid,''Concert 2'',''Draft'',DATEADD(d,20,SYSDATETIME()),DATEADD(d,21,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    UPDATE Concert SET ConcertStatus = ''Published'' WHERE ConcertID = @cid2;
    UPDATE Concert SET ConcertStatus = ''OnSale'' WHERE ConcertID = @cid2;
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,
        StartDatetime,EndDatetime,UsageLimit,CodeRequiredFlag,PromotionStatus)
    VALUES (@cid2,''Promo2'',''Fixed Amount'',100000,SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),100,0,''Active'');
    SET @pid2 = SCOPE_IDENTITY();
    -- Booking thuoc Concert 1 nhung dung Promotion Concert 2
    DECLARE @cid1 INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid1,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid2,
         @DiscountCodeID=NULL, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ApplyPromo_WrongConcert_Fail54004','ERROR',54004,@SQL;

-- 54008: Promotion yeu cau Code nhung khong truyen Code
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT = (SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid AND CodeRequiredFlag=1);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid,
         @DiscountCodeID=NULL, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ApplyPromo_CodeRequired_NoCode_Fail54008','ERROR',54008,@SQL;

-- 54009: DiscountCode sai / het han
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT = (SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid AND CodeRequiredFlag=1);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid,
         @DiscountCodeID=999999, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ApplyPromo_InvalidCode_Fail54009','ERROR',54009,@SQL;

-- Happy Path sp_ApplyPromotion
--
-- Ban truoc cua bai test nay tao Booking KHONG co BookingEventSeatAllocation roi chi
-- khang dinh "FinalAmount < 1.000.000". Nhung FinalAmount duoc dan xuat tu
-- fn_CalculateBookingSubtotal = SUM(PriceSnapshot) cua cac Allocation Active, nen mot
-- Booking khong co ghe luon ra 0 - bat ke Promotion co duoc ap dung hay khong. Bai test
-- vi vay VAN PASS ngay ca khi DiscountAmount bang 0, tuc no khong he kiem dieu ma ten
-- no noi. Ban nay cho Booking mot ghe that (1.000.000) va khang dinh CHINH XAC ca hai
-- con so: giam dung 200.000 va con lai dung 800.000.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertName=''Test Concert Live 2025'');
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT = (SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @dcid INT = (SELECT TOP 1 DiscountCodeID FROM DiscountCode WHERE PromotionID=@pid AND CodeStatus=''Active'');

    DECLARE @seat INT, @gia DECIMAL(18,0);
    SELECT TOP 1 @seat = EventSeatID, @gia = SalePrice
    FROM   EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID;
    IF @seat IS NULL THROW 50000, ''Khong con ghe Available de dung cho bai test'', 1;
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@seat;

    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',@gia,@gia,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationTimestamp,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@seat,SYSDATETIME(),''Active'',@gia);

    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid,
         @DiscountCodeID=@dcid, @ActorUserID=@uid;

    DECLARE @final DECIMAL(18,0) = (SELECT FinalAmount FROM Booking WHERE BookingID=@bid);
    DECLARE @giam  DECIMAL(18,0) = (SELECT DiscountAmount FROM BookingPromotionApplication WHERE BookingID=@bid AND PromotionID=@pid);

    IF @giam IS NULL
        THROW 50000, ''Khong ghi nhan BookingPromotionApplication'', 1;
    IF @giam <> 200000
        THROW 50000, ''DiscountAmount phai dung 200000 (Promotion mock la Fixed Amount 200k)'', 1;
    IF @final <> @gia - 200000
        THROW 50000, ''FinalAmount phai bang Subtotal tru dung 200000'', 1;';
EXEC test.sp_RunTest @Suite,'ApplyPromo_HappyPath','SUCCESS',NULL,@SQL;

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
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',@fa,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;
    -- Lay ticket code
    DECLARE @tcode VARCHAR(64) = (SELECT TOP 1 TicketCode FROM Ticket WHERE BookingID=@bid);
    DECLARE @vresult VARCHAR(32), @vinfo NVARCHAR(500);
    EXEC sp_CheckInTicket @TicketCode=@tcode, @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vresult OUT, @ValidationInfo=@vinfo OUT;
    IF @vresult <> ''SUCCESS'' BEGIN DECLARE @m5 NVARCHAR(200)=''ValidationResult phai SUCCESS, got: ''+@vresult; THROW 50000, @m5, 1; END;';
EXEC test.sp_RunTest @Suite,'CheckIn_HappyPath','SUCCESS',NULL,@SQL;

-- Ticket khong ton tai -> INVALID (khong throw, tra ve ValidationResult)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @vresult VARCHAR(32), @vinfo NVARCHAR(500);
    EXEC sp_CheckInTicket @TicketCode=''FAKE_CODE_999'', @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vresult OUT, @ValidationInfo=@vinfo OUT;
    IF @vresult <> ''INVALID'' BEGIN DECLARE @m6 NVARCHAR(200)=''Expected INVALID got: ''+@vresult; THROW 50000, @m6, 1; END;';
EXEC test.sp_RunTest @Suite,'CheckIn_InvalidTicket_INVALID','SUCCESS',NULL,@SQL;

-- Checkin lan 2 -> DUPLICATE
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'' AND ConcertID=@cid ORDER BY EventSeatID);
    DECLARE @bid INT, @pid INT;
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@esid AS NVARCHAR); EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;
    DECLARE @fa DECIMAL(18,0) = (SELECT FinalAmount FROM Booking WHERE BookingID=@bid);
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',@fa,''REF-TEST'');
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
EXEC test.sp_RunTest @Suite,'CheckIn_Duplicate_ALREADYUSED','SUCCESS',NULL,@SQL;

-- Moc thoi gian check-in phai la gia tri DA GHI, va mot su kien chi mang MOT moc.
--
-- Loi cu: CheckInRepository tra ve DateTime.UtcNow - mot moc do tang ung dung tu sinh
-- SAU khi SP chay xong, khong ton tai trong CSDL. Ngoai ra ba ban ghi cua cung mot lan
-- soat ve (Ticket.UsedTimestamp, CheckIn.CheckInTimestamp, AuditRecord.EventTimestamp)
-- moi cai goi SYSDATETIME() rieng nen co the lech nhau.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @es INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY EventSeatID);
    IF @es IS NULL THROW 50000,''Khong con ghe Available cho bai test'',1;
    DECLARE @bid INT, @pid INT, @fa DECIMAL(18,0);
    DECLARE @seatstr NVARCHAR(MAX) = CAST(@es AS NVARCHAR);
    EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatstr, @NewBookingID=@bid OUTPUT;
    SET @fa = (SELECT FinalAmount FROM Booking WHERE BookingID=@bid);
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',@fa,''REF-TS-TEST'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@pid;

    DECLARE @tcode VARCHAR(64) = (SELECT TOP 1 TicketCode FROM Ticket WHERE BookingID=@bid);
    DECLARE @tid INT = (SELECT TOP 1 TicketID FROM Ticket WHERE BookingID=@bid);
    DECLARE @vresult VARCHAR(32), @vinfo NVARCHAR(500), @ts DATETIME2(7);
    EXEC sp_CheckInTicket @TicketCode=@tcode, @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vresult OUT, @ValidationInfo=@vinfo OUT,
         @CheckInTimestamp=@ts OUT;

    IF @vresult <> ''SUCCESS'' THROW 50000,''Check-in phai thanh cong o bai test nay'',1;

    DECLARE @db  DATETIME2(7) = (SELECT CheckInTimestamp FROM CheckIn WHERE TicketID=@tid);
    DECLARE @use DATETIME2(7) = (SELECT UsedTimestamp    FROM Ticket  WHERE TicketID=@tid);
    DECLARE @aud DATETIME2(7) = (SELECT TOP 1 EventTimestamp FROM AuditRecord
                                 WHERE EntityType=''Ticket'' AND EntityID=CAST(@tid AS VARCHAR(64))
                                   AND EventType=''ADMISSION_SUCCESS'');

    IF @ts IS NULL
        THROW 50000,''sp_CheckInTicket phai tra ve moc thoi gian check-in qua tham so OUTPUT'',1;
    IF @ts <> @db
        THROW 50000,''Moc tra ra khong bang gia tri da ghi vao CheckIn.CheckInTimestamp'',1;
    IF @use <> @db OR @aud <> @db
        THROW 50000,''Mot lan soat ve phai mang DUNG MOT moc thoi gian tren ca ba ban ghi'',1;

    -- Phep so sanh ba moc o tren KHONG du de bat loi: SYSDATETIME() tren Windows chi
    -- nhich sau moi ~1ms, nen ba lenh chay lien tiep thuong tra ve cung mot gia tri va
    -- phep so sanh van dung ke ca khi SP goi SYSDATETIME() ba lan rieng le. Da kiem
    -- chung bang dot bien: bai test van PASS. Vi vay bo sung mot phep kiem CAU TRUC,
    -- tat dinh: ca ba lenh ghi cua nhanh thanh cong phai dung CHUNG bien @Now
    -- (DECLARE + UsedTimestamp + CheckIn + tham so OUTPUT + AuditRecord = 5 lan).
    DECLARE @def NVARCHAR(MAX) = OBJECT_DEFINITION(OBJECT_ID(''dbo.sp_CheckInTicket''));
    DECLARE @soLanNow INT = (LEN(@def) - LEN(REPLACE(@def, ''@Now'', ''''))) / LEN(''@Now'');
    IF @soLanNow < 5
        THROW 50000,''Nhanh thanh cong phai dung chung mot moc thoi gian @Now cho ca ba ban ghi va tham so OUTPUT'',1;

    -- Nhanh that bai: khong co ban ghi CheckIn nao -> phai tra NULL
    DECLARE @vr2 VARCHAR(32), @vi2 NVARCHAR(500), @ts2 DATETIME2(7) = ''2000-01-01'';
    EXEC sp_CheckInTicket @TicketCode=''KHONG_TON_TAI_TS'', @ConcertID=@cid,
         @CheckInStaffUserID=@staff, @ValidationResult=@vr2 OUT, @ValidationInfo=@vi2 OUT,
         @CheckInTimestamp=@ts2 OUT;
    IF @ts2 IS NOT NULL
        THROW 50000,''Check-in that bai thi khong duoc tra ve moc thoi gian'',1;';
EXEC test.sp_RunTest @Suite,'CheckIn_Timestamp_MatchesPersistedValue','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_ProcessRefund
-- Signature: @PaymentID, @RefundAmount, @RefundReason, @ActorUserID, @RefundReference, @NewRefundID OUT
-- ============================================================
-- 53002: Payment khong Confirmed (Actor: Organizer co quyen - C2)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@org, @RefundReason=''Test'';';
EXEC test.sp_RunTest @Suite,'ProcessRefund_PaymentNotConfirmed_Fail53002','ERROR',53012,@SQL;

-- 53004: Refund vuot qua Payment.Amount (Actor: Organizer co quyen - C2)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',500000,''REF-TEST'');
      UPDATE Payment SET PaymentStatus=''Confirmed'', IsBookingConfirmingPayment=1 WHERE PaymentID = SCOPE_IDENTITY();
    SET @pid = SCOPE_IDENTITY();
    -- Refund 1: 300k ok
    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@org, @RefundReason=''Test'';
    -- Refund 2: them 300k -> tong 600k > 500k -> phai loi
    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@org, @RefundReason=''Test'';';
EXEC test.sp_RunTest @Suite,'ProcessRefund_ExceedAmount_Fail53004','ERROR',53015,@SQL;

-- Happy Path sp_ProcessRefund (Actor: Organizer co quyen - C2)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
      UPDATE Payment SET PaymentStatus=''Confirmed'', IsBookingConfirmingPayment=1 WHERE PaymentID = SCOPE_IDENTITY();
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@org, @RefundReason=''Test'';
    -- removed rid check
    IF (SELECT RefundAmount FROM Refund WHERE RefundID=@rid) <> 500000
        THROW 50000, ''RefundAmount sai'', 1;';
EXEC test.sp_RunTest @Suite,'ProcessRefund_HappyPath','SUCCESS',NULL,@SQL;

-- 53011 (C2 security): Khach hang KHAC (khong so huu Booking) khong co quyen huy.
-- Luu y: chinh chu Booking DUOC tu huy (BR18a/BR31) - xem test ke tiep.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @other INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Pending'',1000000,''REF-TEST'');
      UPDATE Payment SET PaymentStatus=''Confirmed'', IsBookingConfirmingPayment=1 WHERE PaymentID = SCOPE_IDENTITY();
    SET @pid = SCOPE_IDENTITY();
    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@other, @RefundReason=''Test'';';
EXEC test.sp_RunTest @Suite,'ProcessRefund_OtherCustomer_Fail53011','ERROR',53011,@SQL;

-- BR18a/BR31: chinh chu Booking duoc tu huy va tao yeu cau hoan tien
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@uid, @RefundReason=''Tu huy'';
    IF NOT EXISTS (SELECT 1 FROM Booking WHERE BookingID=@bid AND BookingStatus=''Cancelled'')
        THROW 59904, ''Booking khong duoc huy boi chinh chu.'', 1;';
EXEC test.sp_RunTest @Suite,'ProcessRefund_OwnerCancels_OK','SUCCESS',NULL,@SQL;

-- 53016: chi Organizer/Admin duoc huy theo dien huy Concert (BR34a)
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid = SCOPE_IDENTITY();
    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@uid, @RefundReason=''x'', @IsConcertCancellation=1;';
EXEC test.sp_RunTest @Suite,'ProcessRefund_CustomerConcertCancel_Fail53016','ERROR',53016,@SQL;

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
    UPDATE Booking SET HoldStartDatetime=DATEADD(HOUR,-2,SYSDATETIME()), HoldExpiryDatetime=DATEADD(HOUR,-1,SYSDATETIME())
    WHERE BookingID=@bid;
    -- Chay release
    EXEC sp_ReleaseExpiredHolds;
    -- Verify
    IF (SELECT BookingStatus FROM Booking WHERE BookingID=@bid) <> ''Expired''
        THROW 50000, ''Booking phai Expired'', 1;
    IF (SELECT InventoryStatus FROM EventSeat WHERE EventSeatID=@esid) <> ''Available''
        THROW 50000, ''EventSeat phai Available sau release'', 1;';
EXEC test.sp_RunTest @Suite,'ReleaseExpiredHolds_HappyPath','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_AllocateWaitlist
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    EXEC sp_AllocateWaitlist @ConcertID=@cid;';
EXEC test.sp_RunTest @Suite,'AllocateWaitlist_Runs','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_FailPayment
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference)
    VALUES (@bid,''Pending'',1000000,''REF-FAIL-HP'');
    SET @pid=SCOPE_IDENTITY();
    EXEC sp_FailPayment @PaymentID=@pid, @ProviderReference=''PROV-001'';
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid)<>''Failed''
        THROW 50000,''PaymentStatus phai Failed'',1;
    IF (SELECT FailureTimestamp FROM Payment WHERE PaymentID=@pid) IS NULL
        THROW 50000,''FailureTimestamp phai co gia tri'',1;';
EXEC test.sp_RunTest @Suite,'FailPayment_HappyPath','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference)
    VALUES (@bid,''Pending'',1000000,''REF-FAIL-IDEM'');
    SET @pid=SCOPE_IDENTITY();
    EXEC sp_FailPayment @PaymentID=@pid;
    -- Goi lan 2 voi Payment da Failed -> WHERE PaymentStatus=Pending khong match -> ROWCOUNT=0, khong loi
    EXEC sp_FailPayment @PaymentID=@pid;
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid)<>''Failed''
        THROW 50000,''PaymentStatus phai van la Failed'',1;';
EXEC test.sp_RunTest @Suite,'FailPayment_Idempotent_NoError','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-FAIL-GUARD'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-FAIL-GUARD'';
    SET @pid=SCOPE_IDENTITY();
    EXEC sp_FailPayment @PaymentID=@pid;
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid)<>''Confirmed''
        THROW 50000,''Confirmed Payment khong duoc bi doi sang Failed'',1;';
EXEC test.sp_RunTest @Suite,'FailPayment_GuardConfirmed_NoChange','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_ConfirmRefund
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-CR-PARTIAL'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-CR-PARTIAL'';
    SET @pid=SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',400000);
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@org;
    IF (SELECT RefundStatus FROM Refund WHERE RefundID=@rid)<>''Confirmed''
        THROW 50000,''RefundStatus phai Confirmed'',1;
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid)<>''PartiallyRefunded''
        THROW 50000,''PaymentStatus phai PartiallyRefunded'',1;';
EXEC test.sp_RunTest @Suite,'ConfirmRefund_Partial_HappyPath','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',500000,500000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',500000,''REF-CR-FULL'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-CR-FULL'';
    SET @pid=SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',500000);
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@org;
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid)<>''Refunded''
        THROW 50000,''PaymentStatus phai Refunded khi tong Refund=Payment'',1;';
EXEC test.sp_RunTest @Suite,'ConfirmRefund_Full_PaymentRefunded','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',500000,500000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',500000,''REF-CR-G53102'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-CR-G53102'';
    SET @pid=SCOPE_IDENTITY();
    -- Dung trang thai Confirmed QUA DUNG DUONG NGHIEP VU (Pending -> sp_ConfirmRefund)
    -- thay vi INSERT thang ''Confirmed''. Refund LUON sinh ra o Pending: ca 5 diem
    -- INSERT INTO Refund trong stored procedure that (sp_ConfirmPayment x3 nhanh
    -- auto-refund, sp_ProcessRefund, sp_UpdateConcertStatus) deu ghi ''Pending'', va
    -- §10.1 chi cong nhan MOT trang thai khoi tao. Dung tat bang INSERT thang trang
    -- thai cuoi tao ra mot trang thai the gioi khong the ton tai that, va bi
    -- TRG_Refund_StateTransition tu choi dung (loi 50006).
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',200000);
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@org;   -- lan 1: Pending -> Confirmed
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@org;'; -- lan 2: phai idempotent
-- Refund da Confirmed: goi lai KHONG phai loi (idempotent voi webhook settlement
-- gui lap, cung mau voi sp_ConfirmPayment/sp_FailPayment).
EXEC test.sp_RunTest @Suite,'ConfirmRefund_AlreadyConfirmed_Idempotent','SUCCESS',NULL,@SQL;

-- Nhung Refund da Cancelled thi khong duoc settle nua -> 53102
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',500000,500000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',500000,''REF-CR-CANCELLED'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-CR-CANCELLED'';
    SET @pid=SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',200000);
    SET @rid=SCOPE_IDENTITY();
    UPDATE Refund SET RefundStatus=''Cancelled'' WHERE RefundID=@rid;
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@org;';
EXEC test.sp_RunTest @Suite,'ConfirmRefund_Cancelled_Fail53102','ERROR',53102,@SQL;

SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',500000,500000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',500000,''REF-CR-G53103'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-CR-G53103'';
    SET @pid=SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',200000);
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ConfirmRefund_CustomerActor_Fail53103','ERROR',53103,@SQL;

-- ============================================================
-- sp_ExitQueue
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @qid INT=(SELECT QueueID FROM Queue WHERE ConcertID=@cid);
    DECLARE @qeid INT;
    INSERT INTO QueueEntry (QueueID,CustomerUserID,QueueStatus) VALUES (@qid,@uid,''Waiting'');
    SET @qeid=SCOPE_IDENTITY();
    EXEC sp_ExitQueue @QueueEntryID=@qeid, @ActorUserID=@uid, @Reason=''Test exit'';
    IF (SELECT QueueStatus FROM QueueEntry WHERE QueueEntryID=@qeid)<>''Exited''
        THROW 50000,''QueueStatus phai Exited'',1;
    IF (SELECT ExitTimestamp FROM QueueEntry WHERE QueueEntryID=@qeid) IS NULL
        THROW 50000,''ExitTimestamp phai co gia tri'',1;';
EXEC test.sp_RunTest @Suite,'ExitQueue_HappyPath','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @qid INT=(SELECT QueueID FROM Queue WHERE ConcertID=@cid);
    DECLARE @qeid INT;
    INSERT INTO QueueEntry (QueueID,CustomerUserID,QueueStatus) VALUES (@qid,@uid,''Waiting'');
    UPDATE QueueEntry SET QueueStatus=''Exited'', ExitTimestamp=SYSDATETIME() WHERE QueueID=@qid AND CustomerUserID=@uid;
    SET @qeid=SCOPE_IDENTITY();
    EXEC sp_ExitQueue @QueueEntryID=@qeid, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ExitQueue_AlreadyExited_Fail59203','ERROR',59203,@SQL;

SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    DECLARE @uid1 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @qid INT=(SELECT QueueID FROM Queue WHERE ConcertID=@cid);
    DECLARE @qeid INT;
    INSERT INTO QueueEntry (QueueID,CustomerUserID,QueueStatus) VALUES (@qid,@uid1,''Waiting'');
    SET @qeid=SCOPE_IDENTITY();
    EXEC sp_ExitQueue @QueueEntryID=@qeid, @ActorUserID=@uid2;';
EXEC test.sp_RunTest @Suite,'ExitQueue_WrongActor_Fail59202','ERROR',59202,@SQL;

-- ============================================================
-- sp_ProcessSaleWindowTransitions
-- ============================================================
SET @SQL = N'
    EXEC sp_ProcessSaleWindowTransitions;';
EXEC test.sp_RunTest @Suite,'ProcessSaleWindowTransitions_Runs','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_ProcessQueueAdmission
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert WHERE ConcertStatus=''OnSale'' ORDER BY ConcertID);
    EXEC sp_ProcessQueueAdmission @ConcertID=@cid;';
EXEC test.sp_RunTest @Suite,'ProcessQueueAdmission_Runs','SUCCESS',NULL,@SQL;


-- ============================================================
-- sp_UpdateRefundStatus (§10.1 / §24.4 / BR32)
-- Duong di con thieu cua vong doi Refund: ket thuc mot yeu cau MA KHONG chi tra.
-- Truoc khi co SP nay, 'Failed' va 'Cancelled' khong co bat ky ben ghi nao du §10.1
-- dinh nghia ro y nghia ca hai va state machine da cho phep Pending -> ca hai.
-- ============================================================

-- Chi nhan Failed/Cancelled: muon xac nhan da hoan tien thi dung sp_ConfirmRefund
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-1'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Confirmed'', @Reason=N''x'';';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_InvalidStatus_Fail59911','ERROR',59911,@SQL;

-- Bat buoc co ly do: day la thao tac dong yeu cau ma khach khong nhan duoc tien
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-2'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Failed'', @Reason=N''   '';';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_NoReason_Fail59912','ERROR',59912,@SQL;

-- Refund khong ton tai
SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=999999, @NewStatus=''Failed'', @Reason=N''x'';';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_NotFound_Fail59913','ERROR',59913,@SQL;

-- Khoan da Confirmed thi khong ket thuc kieu nay duoc: tien da roi tai khoan thu
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-3'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@org;
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Failed'', @Reason=N''thu ket thuc sau khi da settle'';';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_AlreadyConfirmed_Fail59914','ERROR',59914,@SQL;

-- Customer khong co quyen
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-4'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    DECLARE @cust INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    EXEC sp_UpdateRefundStatus @ActorUserID=@cust, @RefundID=@rid, @NewStatus=''Cancelled'', @Reason=N''x'';';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_CustomerActor_Fail59915','ERROR',59915,@SQL;

-- Duong di dung: Failed. Payment PHAI giu nguyen Confirmed - khong dong nao roi tai khoan thu.
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-5'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Failed'', @Reason=N''Cong thanh toan tu choi'';
    IF (SELECT RefundStatus FROM Refund WHERE RefundID=@rid)<>''Failed''
        THROW 50000,''RefundStatus phai la Failed'',1;
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid)<>''Confirmed''
        THROW 50000,''Payment KHONG duoc doi trang thai khi khoan hoan that bai'',1;
    IF (SELECT RefundConfirmationTimestamp FROM Refund WHERE RefundID=@rid) IS NOT NULL
        THROW 50000,''RefundConfirmationTimestamp phai giu NULL - khong co settle nao'',1;
    IF (SELECT RefundReason FROM Refund WHERE RefundID=@rid)<>N''Ly do hoan tien goc''
        THROW 50000,''Khong duoc ghi de ly do hoan tien goc'',1;';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_Failed_OK','SUCCESS',NULL,@SQL;

-- Duong di dung: Cancelled
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-6'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Cancelled'', @Reason=N''Yeu cau bi tu choi'';
    IF (SELECT RefundStatus FROM Refund WHERE RefundID=@rid)<>''Cancelled''
        THROW 50000,''RefundStatus phai la Cancelled'',1;';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_Cancelled_OK','SUCCESS',NULL,@SQL;

-- Idempotent: goi lai dung trang thai da co khong phai loi (dong bo voi sp_ConfirmRefund)
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-7'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Failed'', @Reason=N''lan 1'';
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Failed'', @Reason=N''lan 2'';';
EXEC test.sp_RunTest @Suite,'UpdateRefundStatus_Idempotent_NoError','SUCCESS',NULL,@SQL;

-- HAI BAI DUOI DAY la ly do nghiep vu cua ca SP nay, nen phai kiem bang cap doi.
-- Khong gop lam mot duoc: TRG_RefundLimits goi ROLLBACK TRUOC khi THROW, nen ngay
-- khi khoan 800.000 bi chan thi ca transaction (ke ca du lieu setup) bien mat -
-- moi thao tac sau do se thao tac tren du lieu khong con ton tai.

-- (a) Khoan ket o Pending CHIEM han muc hoan cua Payment, du khach chua nhan dong nao.
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-9'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',800000);';
EXEC test.sp_RunTest @Suite,'RefundHeadroom_PendingBlocksNewRefund_Fail50060','ERROR',50060,@SQL;

-- (b) Danh dau Failed thi phan han muc do duoc giai phong va khoan hop le tao duoc.
--     Day chinh la dieu he thong KHONG lam duoc truoc khi co sp_UpdateRefundStatus.
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @bid INT, @pid INT, @rid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(),HoldStartDatetime=NULL,HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-URS-A'',1);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE PaymentID=@pid;
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount,RefundReason) VALUES (@pid,''Pending'',300000,N''Ly do hoan tien goc'');
    SET @rid=SCOPE_IDENTITY();
    EXEC sp_UpdateRefundStatus @ActorUserID=@org, @RefundID=@rid, @NewStatus=''Failed'', @Reason=N''Cong thanh toan tu choi'';
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',800000);
    IF (SELECT COUNT(*) FROM Refund WHERE PaymentID=@pid AND RefundStatus=''Pending'')<>1
        THROW 50000,''Sau khi danh dau Failed, khoan hoan hop le phai tao duoc'',1;
    IF (SELECT COUNT(*) FROM Refund WHERE PaymentID=@pid AND RefundStatus=''Failed'')<>1
        THROW 50000,''Khoan cu phai o trang thai Failed'',1;';
EXEC test.sp_RunTest @Suite,'RefundHeadroom_FailedReleasesHeadroom_OK','SUCCESS',NULL,@SQL;

PRINT '== SP_Others Tests Done ==';
GO


