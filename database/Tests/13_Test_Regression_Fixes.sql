-- ============================================================
-- 13_Test_Regression_Fixes.sql
-- Test hoi quy cho cac loi da duoc sua trong dot ra soat toan tang DB.
-- Moi test o day tuong ung mot loi CO THAT da duoc tai hien trong san xuat-gia
-- lap truoc khi sua; giu lai de bao dam khong tai phat.
--
-- Du lieu mock (01_SetupMockData): Concert mock dang OnSale, FairAccessEnabled = 0,
-- co san 1 Promotion (CodeRequiredFlag = 1) va 1 DiscountCode Active.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Regression_Fixes';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- 1. TRG_Booking_DiscountUsageGuard: UPDATE nhieu dong phai tru DU so luong
--    Loi cu: `UPDATE dc ... FROM ... JOIN` chi tru 1 lan cho ca lo, lam
--    ReservedUsageCount ro ri vinh vien va khoa cung ma giam gia.
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @u1 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @u2 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @pid INT=(SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @dcid INT=(SELECT TOP 1 DiscountCodeID FROM DiscountCode WHERE PromotionID=@pid);
    DECLARE @before INT=(SELECT ReservedUsageCount FROM DiscountCode WHERE DiscountCodeID=@dcid);
    DECLARE @b1 INT, @b2 INT;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u1,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b1=SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u2,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b2=SCOPE_IDENTITY();

    INSERT INTO BookingPromotionApplication (BookingID,PromotionID,DiscountCodeID,DiscountAmount,AppliedTimestamp,ApplicationOrder)
    VALUES (@b1,@pid,@dcid,200000,SYSDATETIME(),1), (@b2,@pid,@dcid,200000,SYSDATETIME(),1);
    UPDATE DiscountCode SET ReservedUsageCount=ReservedUsageCount+2 WHERE DiscountCodeID=@dcid;

    -- MOT lenh UPDATE cho HAI Booking - dung nhu sp_ReleaseExpiredHolds lam
    UPDATE Booking SET BookingStatus=''Expired'', ExpiredTimestamp=SYSDATETIME()
    WHERE BookingID IN (@b1,@b2);

    DECLARE @after INT=(SELECT ReservedUsageCount FROM DiscountCode WHERE DiscountCodeID=@dcid);
    IF @after <> @before
        THROW 50000,''ReservedUsageCount phai tra ve dung gia tri ban dau cho CA HAI booking'',1;';
EXEC test.sp_RunTest @Suite,'DiscountUsageGuard_MultiRowBatch_DecrementsAll','SUCCESS',NULL,@SQL;

-- Pending -> Confirmed theo lo: Reserved giam du, Consumed tang du
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @u1 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @u2 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @pid INT=(SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @dcid INT=(SELECT TOP 1 DiscountCodeID FROM DiscountCode WHERE PromotionID=@pid);
    DECLARE @consumedBefore INT=(SELECT ConsumedUsageCount FROM DiscountCode WHERE DiscountCodeID=@dcid);
    DECLARE @b1 INT, @b2 INT;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u1,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b1=SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u2,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b2=SCOPE_IDENTITY();

    INSERT INTO BookingPromotionApplication (BookingID,PromotionID,DiscountCodeID,DiscountAmount,AppliedTimestamp,ApplicationOrder)
    VALUES (@b1,@pid,@dcid,200000,SYSDATETIME(),1), (@b2,@pid,@dcid,200000,SYSDATETIME(),1);
    UPDATE DiscountCode SET ReservedUsageCount=ReservedUsageCount+2 WHERE DiscountCodeID=@dcid;

    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME()
    WHERE BookingID IN (@b1,@b2);

    DECLARE @consumedAfter INT=(SELECT ConsumedUsageCount FROM DiscountCode WHERE DiscountCodeID=@dcid);
    IF @consumedAfter <> @consumedBefore + 2
        THROW 50000,''ConsumedUsageCount phai tang dung 2 cho lo hai booking'',1;';
EXEC test.sp_RunTest @Suite,'DiscountUsageGuard_MultiRowConfirm_ConsumesAll','SUCCESS',NULL,@SQL;

-- ============================================================
-- 2. CHK_Booking_TimestampCoherence
--    Confirmed -> Cancelled phai GIU duoc ca hai dau thoi gian.
--    Rang buoc cu (toi da 1 trong 3) khien viec ghi CancelledTimestamp
--    cho mot Booking da Confirmed la bat kha thi.
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@bid;
    UPDATE Booking SET BookingStatus=''Cancelled'', CancelledTimestamp=SYSDATETIME() WHERE BookingID=@bid;
    IF (SELECT ConfirmedTimestamp FROM Booking WHERE BookingID=@bid) IS NULL
        THROW 50000,''ConfirmedTimestamp phai duoc giu lai sau khi huy'',1;
    IF (SELECT CancelledTimestamp FROM Booking WHERE BookingID=@bid) IS NULL
        THROW 50000,''CancelledTimestamp phai duoc ghi khi huy'',1;';
EXEC test.sp_RunTest @Suite,'BookingTimestamp_ConfirmedThenCancelled_KeepsBoth','SUCCESS',NULL,@SQL;

-- Trang thai terminal ma thieu dau thoi gian -> phai bi chan
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Cancelled'' WHERE BookingID=@bid;';
EXEC test.sp_RunTest @Suite,'BookingTimestamp_CancelledWithoutTimestamp_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 3. sp_ProcessRefund: huy Booking Confirmed phai ghi dau thoi gian
--    tren CA Booking lan Ticket.
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @esid INT=(SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid ORDER BY EventSeatID);
    DECLARE @bid INT, @pid INT;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid,''TCK_REG_TS'',''Issued'');
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@bid;
    UPDATE EventSeat SET InventoryStatus=''Booked'' WHERE EventSeatID=@esid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''PAY_REG_TS'',0);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME(),
                       IsBookingConfirmingPayment=1 WHERE PaymentID=@pid;

    EXEC sp_ProcessRefund @BookingID=@bid, @ActorUserID=@adm, @RefundReason=N''regression'';

    IF (SELECT CancelledTimestamp FROM Booking WHERE BookingID=@bid) IS NULL
        THROW 50000,''sp_ProcessRefund phai ghi Booking.CancelledTimestamp'',1;
    IF EXISTS (SELECT 1 FROM Ticket WHERE BookingID=@bid AND TicketStatus=''Cancelled'' AND CancelledTimestamp IS NULL)
        THROW 50000,''sp_ProcessRefund phai ghi Ticket.CancelledTimestamp'',1;
    -- BR32b: Refund duoc tao o trang thai Pending, Payment CHUA duoc coi la Refunded
    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid) <> ''Confirmed''
        THROW 50000,''Payment khong duoc doi trang thai khi Refund con Pending'',1;';
EXEC test.sp_RunTest @Suite,'ProcessRefund_WritesCancelTimestamps','SUCCESS',NULL,@SQL;

-- ============================================================
-- 4. Cascade huy Concert: Payment KHONG duoc tu nhan la da hoan tien
--    khi Refund tuong ung moi chi la Pending (BR32b).
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @cid INT, @bid INT, @pid INT;

    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@art,@ven,''REG Cancel Cascade'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),4,0,0,0);
    SET @cid=SCOPE_IDENTITY();

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',500000,500000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@bid;

    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',500000,''PAY_REG_CC'',0);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME(),
                       IsBookingConfirmingPayment=1 WHERE PaymentID=@pid;

    EXEC sp_UpdateConcertStatus @ConcertID=@cid, @ActorUserID=@adm, @NewStatus=''Cancelled'';

    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid) <> ''Confirmed''
        THROW 50000,''Payment khong duoc dat Refunded khi Refund con Pending (BR32b)'',1;
    IF NOT EXISTS (SELECT 1 FROM Refund WHERE PaymentID=@pid AND RefundStatus=''Pending'' AND RefundAmount=500000)
        THROW 50000,''Cascade phai tao Refund Pending 100%'',1;
    IF (SELECT CancelledTimestamp FROM Booking WHERE BookingID=@bid) IS NULL
        THROW 50000,''Cascade phai ghi Booking.CancelledTimestamp'',1;';
EXEC test.sp_RunTest @Suite,'ConcertCancel_PaymentStaysConfirmed_RefundPending','SUCCESS',NULL,@SQL;

-- Sau khi sp_ConfirmRefund settle -> Payment moi chuyen Refunded
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @cid INT, @bid INT, @pid INT, @rid INT;

    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@art,@ven,''REG Settle'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),4,0,0,0);
    SET @cid=SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',500000,500000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',500000,''PAY_REG_ST'',0);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME(),
                       IsBookingConfirmingPayment=1 WHERE PaymentID=@pid;

    EXEC sp_UpdateConcertStatus @ConcertID=@cid, @ActorUserID=@adm, @NewStatus=''Cancelled'';
    SET @rid=(SELECT TOP 1 RefundID FROM Refund WHERE PaymentID=@pid AND RefundStatus=''Pending'');
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@adm;

    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@pid) <> ''Refunded''
        THROW 50000,''sp_ConfirmRefund phai dua Payment sang Refunded'',1;';
EXEC test.sp_RunTest @Suite,'ConcertCancel_ThenConfirmRefund_PaymentRefunded','SUCCESS',NULL,@SQL;

-- sp_ConfirmRefund idempotent (BR49a): lan hai khong loi, khong cong don
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @cid INT, @bid INT, @pid INT, @rid INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@art,@ven,''REG Idem'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),4,0,0,0);
    SET @cid=SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',500000,500000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@bid;
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',500000,''PAY_REG_ID'',0);
    SET @pid=SCOPE_IDENTITY();
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME(),
                       IsBookingConfirmingPayment=1 WHERE PaymentID=@pid;
    EXEC sp_UpdateConcertStatus @ConcertID=@cid, @ActorUserID=@adm, @NewStatus=''Cancelled'';
    SET @rid=(SELECT TOP 1 RefundID FROM Refund WHERE PaymentID=@pid AND RefundStatus=''Pending'');
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@adm;
    EXEC sp_ConfirmRefund @RefundID=@rid, @ActorUserID=@adm;';
EXEC test.sp_RunTest @Suite,'ConfirmRefund_Idempotent','SUCCESS',NULL,@SQL;

-- ============================================================
-- 5. Fair Access (BR46/BR47/BR47b)
-- ============================================================
-- Khong co admission -> khong duoc dat ve
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @src INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @cid INT, @cat INT, @newb INT;

    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,SaleStartDatetime,SaleEndDatetime,
                         PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@art,@ven,''REG FairAccess Gate'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),
            DATEADD(day,-1,SYSDATETIME()),DATEADD(day,29,SYSDATETIME()),4,1,0,0);
    SET @cid=SCOPE_IDENTITY();
    INSERT INTO TicketCategory (ConcertID,CategoryName,BasePrice,CategoryStatus)
    VALUES (@cid,''REG Cat'',1000000,''Active'');
    SET @cat=SCOPE_IDENTITY();
    INSERT INTO EventSeat (ConcertID,SeatID,TicketCategoryID,InventoryStatus,SalePrice)
    SELECT TOP 1 @cid, SeatID, @cat, ''Available'', 1000000
    FROM Seat WHERE VenueID=@ven ORDER BY SeatID;
    UPDATE Concert SET ConcertStatus=''Published'' WHERE ConcertID=@cid;
    UPDATE Concert SET ConcertStatus=''OnSale''    WHERE ConcertID=@cid;

    EXEC sp_ConfigureQueue @ActorUserID=@adm, @ConcertID=@cid, @AdmissionCapacity=5;

    DECLARE @esid INT=(SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid);
    DECLARE @seatCsv NVARCHAR(20)=CAST(@esid AS NVARCHAR(20));
    EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatCsv,
                          @WaitlistEntryID=NULL, @NewBookingID=@newb OUTPUT;';
EXEC test.sp_RunTest @Suite,'FairAccess_BookingWithoutAdmission_Fail51007','ERROR',51007,@SQL;

-- Co admission -> dat ve duoc, va QueueEntry chuyen Exited (BR47b/QI06)
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @cid INT, @cat INT, @newb INT, @qeid INT;

    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,SaleStartDatetime,SaleEndDatetime,
                         PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@art,@ven,''REG FairAccess Exit'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),
            DATEADD(day,-1,SYSDATETIME()),DATEADD(day,29,SYSDATETIME()),4,1,0,0);
    SET @cid=SCOPE_IDENTITY();
    INSERT INTO TicketCategory (ConcertID,CategoryName,BasePrice,CategoryStatus)
    VALUES (@cid,''REG Cat'',1000000,''Active'');
    SET @cat=SCOPE_IDENTITY();
    INSERT INTO EventSeat (ConcertID,SeatID,TicketCategoryID,InventoryStatus,SalePrice)
    SELECT TOP 1 @cid, SeatID, @cat, ''Available'', 1000000
    FROM Seat WHERE VenueID=@ven ORDER BY SeatID;
    UPDATE Concert SET ConcertStatus=''Published'' WHERE ConcertID=@cid;
    UPDATE Concert SET ConcertStatus=''OnSale''    WHERE ConcertID=@cid;

    EXEC sp_JoinQueue @CustomerUserID=@uid, @ConcertID=@cid, @NewQueueEntryID=@qeid OUTPUT;
    EXEC sp_ProcessQueueAdmission @ConcertID=@cid, @AdmitCount=NULL;
    IF (SELECT QueueStatus FROM QueueEntry WHERE QueueEntryID=@qeid) <> ''Admitted''
        THROW 50000,''QueueEntry phai duoc Admitted truoc khi dat ve'',1;

    DECLARE @esid INT=(SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID=@cid);
    DECLARE @seatCsv NVARCHAR(20)=CAST(@esid AS NVARCHAR(20));
    EXEC sp_CreateBooking @CustomerUserID=@uid, @ConcertID=@cid, @SeatList=@seatCsv,
                          @WaitlistEntryID=NULL, @NewBookingID=@newb OUTPUT;

    IF (SELECT QueueStatus FROM QueueEntry WHERE QueueEntryID=@qeid) <> ''Exited''
        THROW 50000,''BR47b: hoan tat Booking trong han phai chuyen QueueEntry sang Exited'',1;
    IF (SELECT ExitTimestamp FROM QueueEntry WHERE QueueEntryID=@qeid) IS NULL
        THROW 50000,''ExitTimestamp phai duoc ghi khi roi hang'',1;';
EXEC test.sp_RunTest @Suite,'FairAccess_BookingWithAdmission_ExitsQueue','SUCCESS',NULL,@SQL;

-- BR46: khong duoc co hai QueueEntry dang hoat dong cho cung Customer
SET @SQL = N'
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @qid INT=(SELECT TOP 1 QueueID FROM Queue ORDER BY QueueID);
    INSERT INTO QueueEntry (QueueID,CustomerUserID,QueueStatus) VALUES (@qid,@uid,''Waiting'');
    INSERT INTO QueueEntry (QueueID,CustomerUserID,QueueStatus) VALUES (@qid,@uid,''Waiting'');';
EXEC test.sp_RunTest @Suite,'QueueEntry_DuplicateActive_Blocked','ERROR',NULL,@SQL;

-- ============================================================
-- 6. Cau hinh Fair Access / Waitlist: RANDOM phai dat toi duoc (FR64a, BR43/BR45b)
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    UPDATE Concert SET FairAccessEnabled=1 WHERE ConcertID=@cid;
    EXEC sp_ConfigureQueue @ActorUserID=@adm, @ConcertID=@cid,
         @AdmissionCapacity=250, @FairAccessPolicy=''RANDOM'', @AdmissionValiditySeconds=300;
    IF NOT EXISTS (SELECT 1 FROM Queue WHERE ConcertID=@cid AND FairAccessPolicy=''RANDOM''
                     AND AdmissionCapacity=250 AND AdmissionValiditySeconds=300)
        THROW 50000,''sp_ConfigureQueue phai ghi duoc RANDOM/capacity/booking_ttl'',1;';
EXEC test.sp_RunTest @Suite,'ConfigureQueue_SetsRandomPolicyAndTtl','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    EXEC sp_ConfigureWaitlist @ActorUserID=@adm, @ConcertID=@cid, @AllocationPolicy=''RANDOM'';
    IF NOT EXISTS (SELECT 1 FROM Waitlist WHERE ConcertID=@cid AND AllocationPolicy=''RANDOM'')
        THROW 50000,''sp_ConfigureWaitlist phai ghi duoc RANDOM'',1;';
EXEC test.sp_RunTest @Suite,'ConfigureWaitlist_SetsRandomPolicy','SUCCESS',NULL,@SQL;

-- Khong duoc mo Queue khi Concert chua bat FairAccessEnabled (§12.15.1)
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @cid INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@art,@ven,''REG NoFair'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),4,0,0,0);
    SET @cid=SCOPE_IDENTITY();
    EXEC sp_ConfigureQueue @ActorUserID=@adm, @ConcertID=@cid, @AdmissionCapacity=10;';
EXEC test.sp_RunTest @Suite,'ConfigureQueue_FairAccessOff_Fail59507','ERROR',59507,@SQL;

-- ============================================================
-- 7. Vong doi du lieu danh muc (FR59b / BR50e)
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT, @zid INT, @sid INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''REG Venue'', @Address=N''x'', @NewVenueID=@ven OUTPUT;
    EXEC sp_CreateZone  @ActorUserID=@adm, @VenueID=@ven, @ZoneCode=''REGZ'', @ZoneName=N''z'', @NewZoneID=@zid OUTPUT;
    EXEC sp_CreateSeat  @ActorUserID=@adm, @ZoneID=@zid, @SeatCode=''REGS'', @SeatLabel=N''s'', @SeatRowLabel=N''A'', @SeatColumnNumber=1, @NewSeatID=@sid OUTPUT;

    EXEC sp_UpdateSeat  @ActorUserID=@adm, @SeatID=@sid,  @SeatStatus=''Retired'';
    EXEC sp_UpdateZone  @ActorUserID=@adm, @ZoneID=@zid,  @ZoneStatus=''Retired'';
    EXEC sp_UpdateVenue @ActorUserID=@adm, @VenueID=@ven, @VenueStatus=''Inactive'';

    IF (SELECT SeatStatus  FROM Seat  WHERE SeatID=@sid)  <> ''Retired''  THROW 50000,''Seat phai Retired'',1;
    IF (SELECT ZoneStatus  FROM Zone  WHERE ZoneID=@zid)  <> ''Retired''  THROW 50000,''Zone phai Retired'',1;
    IF (SELECT VenueStatus FROM Venue WHERE VenueID=@ven) <> ''Inactive'' THROW 50000,''Venue phai Inactive'',1;';
EXEC test.sp_RunTest @Suite,'CatalogLifecycle_RetireSeatZoneVenue_OK','SUCCESS',NULL,@SQL;

-- Ghe da Retired khong duoc dua vao kho ve moi (58219) - lop kiem tra nay truoc
-- day khong the kich hoat vi khong ai dat duoc trang thai Retired.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @cat INT=(SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @ven INT=(SELECT VenueID FROM Concert WHERE ConcertID=@cid);
    DECLARE @zid INT, @sid INT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@ven, @ZoneCode=''REGZ2'', @ZoneName=N''z'', @NewZoneID=@zid OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@zid, @SeatCode=''REGS2'', @SeatLabel=N''s'', @SeatRowLabel=N''A'', @SeatColumnNumber=1, @NewSeatID=@sid OUTPUT;
    EXEC sp_UpdateSeat @ActorUserID=@adm, @SeatID=@sid, @SeatStatus=''Retired'';
    UPDATE Concert SET ConcertStatus=''SaleClosed'' WHERE ConcertID=@cid;
    UPDATE Concert SET ConcertStatus=''OnSale''     WHERE ConcertID=@cid;
    DECLARE @csv NVARCHAR(20)=CAST(@sid AS NVARCHAR(20));
    EXEC sp_AddEventSeats @ActorUserID=@adm, @ConcertID=@cid, @TicketCategoryID=@cat, @SeatIDs=@csv;';
EXEC test.sp_RunTest @Suite,'CatalogLifecycle_RetiredSeat_RejectedByAddEventSeats','ERROR',NULL,@SQL;

-- Khong duoc Retire ghe dang nam trong kho ve cua Concert chua ket thuc
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @sid INT=(SELECT TOP 1 SeatID FROM EventSeat WHERE ConcertID=@cid);
    EXEC sp_UpdateSeat @ActorUserID=@adm, @SeatID=@sid, @SeatStatus=''Retired'';';
EXEC test.sp_RunTest @Suite,'CatalogLifecycle_RetireSeatInUse_Fail59425','ERROR',59425,@SQL;

-- ============================================================
-- 8. Vong doi khuyen mai (FR52 / FR53b)
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @pid INT=(SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @dcid INT=(SELECT TOP 1 DiscountCodeID FROM DiscountCode WHERE PromotionID=@pid);
    EXEC sp_UpdatePromotionStatus @ActorUserID=@adm, @PromotionID=@pid, @NewStatus=''Disabled'';
    IF (SELECT PromotionStatus FROM Promotion WHERE PromotionID=@pid) <> ''Disabled''
        THROW 50000,''Promotion phai chuyen duoc sang Disabled'',1;
    EXEC sp_UpdateDiscountCodeStatus @ActorUserID=@adm, @DiscountCodeID=@dcid, @NewStatus=''Disabled'';
    IF (SELECT CodeStatus FROM DiscountCode WHERE DiscountCodeID=@dcid) <> ''Disabled''
        THROW 50000,''DiscountCode phai thu hoi duoc'',1;';
EXEC test.sp_RunTest @Suite,'PromotionLifecycle_DisablePromotionAndCode','SUCCESS',NULL,@SQL;

-- Ma da thu hoi thi khong ap dung duoc nua (54009)
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT=(SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @dcid INT=(SELECT TOP 1 DiscountCodeID FROM DiscountCode WHERE PromotionID=@pid);
    DECLARE @bid INT;
    EXEC sp_UpdateDiscountCodeStatus @ActorUserID=@adm, @DiscountCodeID=@dcid, @NewStatus=''Disabled'';
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid, @DiscountCodeID=@dcid, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'PromotionLifecycle_DisabledCodeRejected_Fail54009','ERROR',54009,@SQL;

-- sp_ApplyPromotion phai kiem tra ma NGAY CA khi CodeRequiredFlag = 0
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT, @dcid INT, @bid INT;
    DECLARE @ps DATETIME2(7)=DATEADD(day,-1,SYSDATETIME());
    DECLARE @pe DATETIME2(7)=DATEADD(day,10,SYSDATETIME());
    -- Promotion KHONG yeu cau code, nhung van co code va co han muc toan cuc = 1
    EXEC sp_CreatePromotion @ActorUserID=@adm, @ConcertID=@cid, @PromotionName=N''REG NoCodeReq'',
         @PromotionDescription=N''d'', @DiscountType=''Fixed Amount'', @DiscountValue=1000,
         @StartDatetime=@ps, @EndDatetime=@pe, @UsageLimit=NULL, @CodeRequiredFlag=0,
         @NewPromotionID=@pid OUTPUT;
    EXEC sp_CreateDiscountCode @ActorUserID=@adm, @PromotionID=@pid, @CodeValue=''REGNC'',
         @ValidFromDatetime=NULL, @ValidToDatetime=NULL, @GlobalUsageLimit=1,
         @NewDiscountCodeID=@dcid OUTPUT;
    -- Dat truoc han muc toan cuc ve muc da dung het
    UPDATE DiscountCode SET ConsumedUsageCount=1 WHERE DiscountCodeID=@dcid;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid, @DiscountCodeID=@dcid, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ApplyPromotion_CodeValidatedWhenNotRequired_Fail54011','ERROR',54011,@SQL;

-- ============================================================
-- 9. Thu hoi phan cong Check-in Staff (BR39/FR51)
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @stf INT=(SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @csv NVARCHAR(20)=CAST(@cid AS NVARCHAR(20));
    EXEC sp_AddCheckinStaffAssignment @ActorUserID=@adm, @StaffUserID=@stf,
         @ConcertIDs=@csv, @AssignmentStatus=''Revoked'';
    IF (SELECT AssignmentStatus FROM CheckinStaffAssignment WHERE UserID=@stf AND ConcertID=@cid) <> ''Revoked''
        THROW 50000,''Phan cong phai thu hoi duoc'',1;
    -- Gan lai
    EXEC sp_AddCheckinStaffAssignment @ActorUserID=@adm, @StaffUserID=@stf,
         @ConcertIDs=@csv, @AssignmentStatus=''Active'';
    IF (SELECT AssignmentStatus FROM CheckinStaffAssignment WHERE UserID=@stf AND ConcertID=@cid) <> ''Active''
        THROW 50000,''Phan cong phai gan lai duoc'',1;';
EXEC test.sp_RunTest @Suite,'CheckinStaffAssignment_RevokeAndReassign','SUCCESS',NULL,@SQL;

-- ============================================================
-- 10. TicketCategory: chuyen Inactive (FR12)
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @cid INT, @cat INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@org,@art,@ven,''REG CatStatus'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),4,0,0,0);
    SET @cid=SCOPE_IDENTITY();
    EXEC sp_ConfigureTicketCategory @ActorUserID=@adm, @ConcertID=@cid, @CategoryName=N''REG C'',
         @CategoryDescription=N''d'', @BasePrice=100000, @TicketCategoryID=@cat OUTPUT;
    EXEC sp_ConfigureTicketCategory @ActorUserID=@adm, @ConcertID=@cid, @CategoryName=N''REG C'',
         @CategoryDescription=N''d'', @BasePrice=100000, @CategoryStatus=''Inactive'',
         @TicketCategoryID=@cat OUTPUT;
    IF (SELECT CategoryStatus FROM TicketCategory WHERE TicketCategoryID=@cat) <> ''Inactive''
        THROW 50000,''CategoryStatus phai chuyen duoc sang Inactive'',1;';
EXEC test.sp_RunTest @Suite,'TicketCategory_SetInactive_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 11. CHECK moi tren Concert
-- ============================================================
SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused,
                         RefundPercentage)
    VALUES (@org,@art,@ven,''REG BadPct'',''Draft'',
            DATEADD(day,30,SYSDATETIME()),DATEADD(day,31,SYSDATETIME()),4,0,0,0, 250.00);';
EXEC test.sp_RunTest @Suite,'CHK_Concert_RefundPercentage_Over100_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 12. TRG_AuditLog khong duoc rollback khi lenh khong tac dong dong nao
-- ============================================================
SET @SQL = N'DELETE FROM AuditRecord WHERE AuditID = -1;';
EXEC test.sp_RunTest @Suite,'AuditLog_ZeroRowDelete_NoRollback','SUCCESS',NULL,@SQL;

-- Nhung xoa that su thi van bi chan
SET @SQL = N'
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    INSERT INTO AuditRecord (ActorUserID,EventType,EntityType,EntityID,Action)
    VALUES (@uid,''REG_TEST'',''UserAccount'',CAST(@uid AS VARCHAR(64)),''INSERT'');
    DECLARE @aid INT=SCOPE_IDENTITY();
    DELETE FROM AuditRecord WHERE AuditID=@aid;';
EXEC test.sp_RunTest @Suite,'AuditLog_RealDelete_Blocked50100','ERROR',50100,@SQL;

-- ============================================================
-- 13. sp_CreateConcert phai kiem tra Actor (58008)
-- ============================================================
SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cus INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @st DATETIME2(7)=DATEADD(day,30,SYSDATETIME());
    DECLARE @en DATETIME2(7)=DATEADD(day,31,SYSDATETIME());
    DECLARE @cid INT;
    EXEC sp_CreateConcert @OrganizerUserID=@org, @ArtistID=@art, @VenueID=@ven,
         @ConcertName=N''REG Actor'', @StartDatetime=@st, @EndDatetime=@en,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4,
         @TemporaryHoldDuration=900, @CancellationPolicy=N''c'', @RefundPolicy=N''r'',
         @ActorUserID=@cus, @NewConcertID=@cid OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcert_ForeignActor_Fail58008','ERROR',58008,@SQL;

-- ============================================================
-- 14. LO MAT TIEN: ap khuyen mai sau khi da khoi tao thanh toan
--     Kich ban that: khach bam "Thanh toan" (Payment chup Amount=1000000), roi ap ma
--     khuyen mai lam FinalAmount giam; cong thanh toan thu tien va bao thanh cong;
--     sp_ConfirmPayment cu ROLLBACK toan bo -> tien da thu nhung DB khong biet, khong
--     co ve, khong co refund. Nay chan tu HAI dau doc lap nhau.
-- ============================================================

-- Dau 1 (A1): khong duoc doi gia don hang khi dang co Payment Pending
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT=(SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference)
    VALUES (@bid,''Pending'',1000000,''REG-LOCKPRICE'');
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid, @DiscountCodeID=NULL, @ActorUserID=@uid;';
EXEC test.sp_RunTest @Suite,'ApplyPromotion_WhilePaymentPending_Fail54013','ERROR',54013,@SQL;

-- Huy lan thanh toan do (sp_FailPayment) roi ap khuyen mai thi lai duoc
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @ps DATETIME2(7)=DATEADD(day,-1,SYSDATETIME());
    DECLARE @pe DATETIME2(7)=DATEADD(day,10,SYSDATETIME());
    DECLARE @pid INT, @bid INT, @payid INT;
    EXEC sp_CreatePromotion @ActorUserID=@adm, @ConcertID=@cid, @PromotionName=N''REG Unlock'',
         @PromotionDescription=N''d'', @DiscountType=''Fixed Amount'', @DiscountValue=1000,
         @StartDatetime=@ps, @EndDatetime=@pe, @UsageLimit=NULL, @CodeRequiredFlag=0,
         @NewPromotionID=@pid OUTPUT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference)
    VALUES (@bid,''Pending'',1000000,''REG-UNLOCK'');
    SET @payid=SCOPE_IDENTITY();
    EXEC sp_FailPayment @PaymentID=@payid;
    EXEC sp_ApplyPromotion @BookingID=@bid, @PromotionID=@pid, @DiscountCodeID=NULL, @ActorUserID=@uid;
    -- Kiem dung dieu dang xet: khoa gia da duoc go sau khi giao dich thanh toan bi huy.
    -- KHONG khang dinh gia tri FinalAmount o day: Booking trong test duoc chen truc tiep
    -- nen khong co BookingEventSeatAllocation, ma fn_CalculateFinalAmount tinh Subtotal
    -- tu tong PriceSnapshot cua cac Allocation dang Active -> ket qua se la 0, khong phai
    -- 1000000 - 1000. Do la dac diem cua du lieu test, khong phai hanh vi can kiem.
    IF NOT EXISTS (SELECT 1 FROM BookingPromotionApplication WHERE BookingID=@bid AND PromotionID=@pid)
        THROW 50000,''Sau khi huy thanh toan, khuyen mai phai ap dung duoc'',1;';
EXEC test.sp_RunTest @Suite,'ApplyPromotion_AfterFailingPayment_OK','SUCCESS',NULL,@SQL;

-- Dau 2 (A2): du co lech tien (vd cong thanh toan gui sai so), tien da thu KHONG
-- duoc vut bo - phai sinh Refund. Lop bao ve nay doc lap voi A1.
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @payid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference)
    VALUES (@bid,''Pending'',800000,''REG-MISMATCH'');
    SET @payid=SCOPE_IDENTITY();
    EXEC sp_ConfirmPayment @BookingID=@bid, @PaymentID=@payid;

    IF (SELECT PaymentStatus FROM Payment WHERE PaymentID=@payid) <> ''Confirmed''
        THROW 50000,''Tien da thu phai duoc ghi nhan, khong duoc ROLLBACK'',1;
    IF (SELECT IsBookingConfirmingPayment FROM Payment WHERE PaymentID=@payid) <> 0
        THROW 50000,''Payment lech tien khong duoc gianh quyen hieu luc'',1;
    IF NOT EXISTS (SELECT 1 FROM Refund WHERE PaymentID=@payid AND RefundStatus=''Pending'' AND RefundAmount=800000)
        THROW 50000,''Phai sinh Refund cho khoan tien lech'',1;
    IF NOT EXISTS (SELECT 1 FROM AuditRecord WHERE EntityType=''Payment''
                     AND EntityID=CAST(@payid AS VARCHAR(64)) AND EventType=''PAYMENT_AUTO_REFUNDED'')
        THROW 50000,''Phai ghi Audit cho khoan hoan tu dong'',1;
    IF (SELECT BookingStatus FROM Booking WHERE BookingID=@bid) <> ''Pending''
        THROW 50000,''Booking phai o nguyen Pending de khach tra lai dung so tien'',1;';
EXEC test.sp_RunTest @Suite,'ConfirmPayment_AmountMismatch_RefundsNotRollback','SUCCESS',NULL,@SQL;

-- ============================================================
-- 15. HAN MUC KHUYEN MAI (B): quota khong duoc dot boi don khong bao gio thanh don
-- ============================================================

-- Don het han KHONG tinh luot -> khach thu hai van dung duoc
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @u1 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @u2 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @ps DATETIME2(7)=DATEADD(day,-1,SYSDATETIME());
    DECLARE @pe DATETIME2(7)=DATEADD(day,10,SYSDATETIME());
    DECLARE @pid INT, @b1 INT, @b2 INT;
    EXEC sp_CreatePromotion @ActorUserID=@adm, @ConcertID=@cid, @PromotionName=N''REG Quota'',
         @PromotionDescription=N''d'', @DiscountType=''Fixed Amount'', @DiscountValue=1000,
         @StartDatetime=@ps, @EndDatetime=@pe, @UsageLimit=1, @CodeRequiredFlag=0,
         @NewPromotionID=@pid OUTPUT;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u1,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b1=SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@b1, @PromotionID=@pid, @DiscountCodeID=NULL, @ActorUserID=@u1;
    UPDATE Booking SET BookingStatus=''Expired'', ExpiredTimestamp=SYSDATETIME() WHERE BookingID=@b1;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u2,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b2=SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@b2, @PromotionID=@pid, @DiscountCodeID=NULL, @ActorUserID=@u2;';
EXEC test.sp_RunTest @Suite,'PromotionUsageLimit_ExpiredBookingDoesNotBurnQuota','SUCCESS',NULL,@SQL;

-- Nhung don DA THANH DON roi bi huy thi VAN tinh luot: chong vong dat-huy de xai lai
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @u1 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @u2 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @ps DATETIME2(7)=DATEADD(day,-1,SYSDATETIME());
    DECLARE @pe DATETIME2(7)=DATEADD(day,10,SYSDATETIME());
    DECLARE @pid INT, @b1 INT, @b2 INT;
    EXEC sp_CreatePromotion @ActorUserID=@adm, @ConcertID=@cid, @PromotionName=N''REG Quota2'',
         @PromotionDescription=N''d'', @DiscountType=''Fixed Amount'', @DiscountValue=1000,
         @StartDatetime=@ps, @EndDatetime=@pe, @UsageLimit=1, @CodeRequiredFlag=0,
         @NewPromotionID=@pid OUTPUT;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u1,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b1=SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@b1, @PromotionID=@pid, @DiscountCodeID=NULL, @ActorUserID=@u1;
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME() WHERE BookingID=@b1;
    UPDATE Booking SET BookingStatus=''Cancelled'', CancelledTimestamp=SYSDATETIME() WHERE BookingID=@b1;

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u2,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @b2=SCOPE_IDENTITY();
    EXEC sp_ApplyPromotion @BookingID=@b2, @PromotionID=@pid, @DiscountCodeID=NULL, @ActorUserID=@u2;';
EXEC test.sp_RunTest @Suite,'PromotionUsageLimit_ConfirmedThenCancelled_StillCounts','ERROR',54007,@SQL;

-- ============================================================
-- 16. sp_AllocateWaitlist (F): khoa, gioi han lo, va chinh sach RANDOM
-- ============================================================

-- Applock phai co pham vi TRANSACTION, khong phai SESSION.
-- Day chinh la loi cu: khoa 'Session' khong gan voi transaction nao, nen mot lan chay
-- bi bo do (client cancel / timeout / kill) se giu khoa mai; moi lan SIP2 sau do cho
-- Concert do lang le thoat ra o `IF @LockResult < 0 RETURN` - waitlist ngung phan bo
-- ma khong co dau hieu gi.
--
-- LUU Y VE CACH KIEM: KHONG dung APPLOCK_TEST o day. sp_RunTest boc doan test trong
-- transaction cua chinh no, nen BEGIN/COMMIT ben trong sp_AllocateWaitlist chi lam
-- tang/giam @@TRANCOUNT chu khong ket thuc transaction - khoa van con duoc giu, va
-- APPLOCK_TEST hoi tu CHINH phien dang giu khoa se luon tra ve "cap duoc". Mot phep
-- kiem nhu vay PASS RONG, khong chung minh dieu gi.
-- Cach dung: soi truc tiep sys.dm_tran_locks va khang dinh CHU SO HUU cua khoa la
-- TRANSACTION - dung thuoc tinh da duoc sua.
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    EXEC sp_AllocateWaitlist @ConcertID=@cid;

    DECLARE @n INT = (SELECT COUNT(*) FROM sys.dm_tran_locks
                      WHERE request_session_id = @@SPID
                        AND resource_type = ''APPLICATION''
                        AND resource_description LIKE ''%WaitlistAlloc%'');
    IF @n = 0
        THROW 50000,''SP khong he lay applock - phep kiem se pass rong, xem lai du lieu mock'',1;

    IF EXISTS (SELECT 1 FROM sys.dm_tran_locks
               WHERE request_session_id = @@SPID
                 AND resource_type = ''APPLICATION''
                 AND resource_description LIKE ''%WaitlistAlloc%''
                 AND request_owner_type <> ''TRANSACTION'')
        THROW 50000,''Applock phai co pham vi TRANSACTION de duoc nha tu dong khi ket thuc giao dich'',1;';
EXEC test.sp_RunTest @Suite,'AllocateWaitlist_AppLockIsTransactionScoped','SUCCESS',NULL,@SQL;

-- Chinh sach RANDOM phai chay duoc (truoc day khong the dat toi -> nhanh code chet)
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    UPDATE Concert SET WaitlistEnabled=1 WHERE ConcertID=@cid;
    EXEC sp_ConfigureWaitlist @ActorUserID=@adm, @ConcertID=@cid, @AllocationPolicy=''RANDOM'';
    EXEC sp_AllocateWaitlist @ConcertID=@cid;';
EXEC test.sp_RunTest @Suite,'AllocateWaitlist_RandomPolicy_Runs','SUCCESS',NULL,@SQL;

-- All-or-nothing (BR42b) + khong skip-ahead (CI07) van dung sau khi tai cau truc:
-- entry dau doi 3 ghe nhung chi con 2 -> khong ai duoc cap, ke ca entry sau chi doi 1.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @u1  INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @u2  INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @cat INT=(SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @wid INT, @e1 INT, @e2 INT;

    -- Chi de lai DUNG 2 ghe Available trong Category nay
    UPDATE EventSeat SET InventoryStatus=''Unavailable'', UnavailabilityReason=N''test''
    WHERE EventSeatID IN (SELECT TOP 100 PERCENT EventSeatID FROM EventSeat
                          WHERE ConcertID=@cid AND TicketCategoryID=@cat AND InventoryStatus=''Available''
                          ORDER BY EventSeatID)
      AND EventSeatID NOT IN (SELECT TOP 2 EventSeatID FROM EventSeat
                              WHERE ConcertID=@cid AND TicketCategoryID=@cat AND InventoryStatus=''Available''
                              ORDER BY EventSeatID);

    UPDATE Concert SET WaitlistEnabled=1 WHERE ConcertID=@cid;
    EXEC sp_ConfigureWaitlist @ActorUserID=@adm, @ConcertID=@cid, @AllocationPolicy=''FIFO'';
    SET @wid=(SELECT WaitlistID FROM Waitlist WHERE ConcertID=@cid);
    DELETE FROM WaitlistEntry WHERE WaitlistID=@wid;

    INSERT INTO WaitlistEntry (WaitlistID,CustomerUserID,TicketCategoryID,RequestedQuantity,JoinedTimestamp,QueuePosition,EntryStatus)
    VALUES (@wid,@u1,@cat,3,DATEADD(minute,-10,SYSDATETIME()),1,''Active'');
    SET @e1=SCOPE_IDENTITY();
    INSERT INTO WaitlistEntry (WaitlistID,CustomerUserID,TicketCategoryID,RequestedQuantity,JoinedTimestamp,QueuePosition,EntryStatus)
    VALUES (@wid,@u2,@cat,1,DATEADD(minute,-5,SYSDATETIME()),2,''Active'');
    SET @e2=SCOPE_IDENTITY();

    EXEC sp_AllocateWaitlist @ConcertID=@cid;

    IF (SELECT EntryStatus FROM WaitlistEntry WHERE WaitlistEntryID=@e1) <> ''Active''
        THROW 50000,''BR42b: entry doi 3 ghe khi chi con 2 thi khong duoc cap tung phan'',1;
    IF (SELECT EntryStatus FROM WaitlistEntry WHERE WaitlistEntryID=@e2) <> ''Active''
        THROW 50000,''CI07: khong duoc skip-ahead phuc vu entry sau trong cung Category'',1;';
EXEC test.sp_RunTest @Suite,'AllocateWaitlist_AllOrNothing_NoSkipAhead','SUCCESS',NULL,@SQL;

-- Du ghe thi cap dung RequestedQuantity va tao du dong Allocation
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @u1  INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @cat INT=(SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @wid INT, @e1 INT;
    UPDATE Concert SET WaitlistEnabled=1 WHERE ConcertID=@cid;
    EXEC sp_ConfigureWaitlist @ActorUserID=@adm, @ConcertID=@cid, @AllocationPolicy=''FIFO'';
    SET @wid=(SELECT WaitlistID FROM Waitlist WHERE ConcertID=@cid);
    DELETE FROM WaitlistEntry WHERE WaitlistID=@wid;
    INSERT INTO WaitlistEntry (WaitlistID,CustomerUserID,TicketCategoryID,RequestedQuantity,JoinedTimestamp,QueuePosition,EntryStatus)
    VALUES (@wid,@u1,@cat,2,SYSDATETIME(),1,''Active'');
    SET @e1=SCOPE_IDENTITY();

    EXEC sp_AllocateWaitlist @ConcertID=@cid;

    IF (SELECT EntryStatus FROM WaitlistEntry WHERE WaitlistEntryID=@e1) <> ''Granted''
        THROW 50000,''Du ghe thi phai cap co hoi'',1;
    IF (SELECT COUNT(*) FROM WaitlistEntryEventSeatAllocation
        WHERE WaitlistEntryID=@e1 AND AllocationStatus=''Active'') <> 2
        THROW 50000,''Phai tao dung 2 dong Allocation'',1;
    IF (SELECT COUNT(*) FROM EventSeat WHERE ConcertID=@cid AND InventoryStatus=''OnHoldForWaitlist'') <> 2
        THROW 50000,''Phai giu dung 2 ghe sang OnHoldForWaitlist'',1;
    IF (SELECT OpportunityExpiryTimestamp FROM WaitlistEntry WHERE WaitlistEntryID=@e1) IS NULL
        THROW 50000,''Phai dat han su dung co hoi'',1;';
EXEC test.sp_RunTest @Suite,'AllocateWaitlist_GrantsFullQuantity','SUCCESS',NULL,@SQL;

-- @MaxEntriesPerRun gioi han dung khoi luong moi lan chay
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @u1  INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @u2  INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @cat INT=(SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @wid INT;
    UPDATE Concert SET WaitlistEnabled=1 WHERE ConcertID=@cid;
    EXEC sp_ConfigureWaitlist @ActorUserID=@adm, @ConcertID=@cid, @AllocationPolicy=''FIFO'';
    SET @wid=(SELECT WaitlistID FROM Waitlist WHERE ConcertID=@cid);
    DELETE FROM WaitlistEntry WHERE WaitlistID=@wid;
    INSERT INTO WaitlistEntry (WaitlistID,CustomerUserID,TicketCategoryID,RequestedQuantity,JoinedTimestamp,QueuePosition,EntryStatus)
    VALUES (@wid,@u1,@cat,1,DATEADD(minute,-10,SYSDATETIME()),1,''Active''),
           (@wid,@u2,@cat,1,DATEADD(minute,-5,SYSDATETIME()),2,''Active'');

    EXEC sp_AllocateWaitlist @ConcertID=@cid, @MaxEntriesPerRun=1;

    IF (SELECT COUNT(*) FROM WaitlistEntry WHERE WaitlistID=@wid AND EntryStatus=''Granted'') <> 1
        THROW 50000,''@MaxEntriesPerRun=1 chi duoc xu ly dung mot entry'',1;';
EXEC test.sp_RunTest @Suite,'AllocateWaitlist_MaxEntriesPerRun_BoundsBatch','SUCCESS',NULL,@SQL;

-- ============================================================
-- 17. Index cua AuditRecord (E) phai ton tai va duoc dung
-- ============================================================
SET @SQL = N'
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''dbo.AuditRecord'') AND name=''IX_AuditRecord_Entity'')
        THROW 50000,''Thieu IX_AuditRecord_Entity'',1;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''dbo.AuditRecord'') AND name=''IX_AuditRecord_Timestamp'')
        THROW 50000,''Thieu IX_AuditRecord_Timestamp'',1;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''dbo.AuditRecord'') AND name=''IX_AuditRecord_Actor'')
        THROW 50000,''Thieu IX_AuditRecord_Actor'',1;
    IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(''dbo.AuditRecord'')
                     AND name=''IX_AuditRecord_TransactionRef'' AND has_filter=1)
        THROW 50000,''Thieu IX_AuditRecord_TransactionRef (phai la filtered index)'',1;
    -- Khong duoc INCLUDE cot NVARCHAR(MAX) vao index: se nhan ban toan bo JSON
    IF EXISTS (SELECT 1
               FROM sys.index_columns ic
               JOIN sys.columns c ON c.object_id=ic.object_id AND c.column_id=ic.column_id
               JOIN sys.indexes i ON i.object_id=ic.object_id AND i.index_id=ic.index_id
               WHERE ic.object_id=OBJECT_ID(''dbo.AuditRecord'')
                 AND i.name LIKE ''IX_AuditRecord%''
                 AND c.name IN (''PreviousValue'',''NewValue''))
        THROW 50000,''Khong duoc dua PreviousValue/NewValue vao index'',1;';
EXEC test.sp_RunTest @Suite,'AuditRecord_IndexesExist','SUCCESS',NULL,@SQL;

-- ============================================================
-- 18. BR36d/PI06: thu tu ap dung Promotion phai la thu tu TAO, khong phai thu tu
--     khach bam.
--     Loi cu: sp_ApplyPromotion gan ApplicationOrder = MAX+1 va tinh discount tren
--     Booking.FinalAmount doc tai thoi diem bam, nen thu tu thao tac cua nguoi dung
--     quyet dinh so tien. Do duoc tren DB that: cung tam tinh 1.500.000 va cung hai
--     Promotion (Fixed 200k tao truoc, Percentage 10 tao sau), bam Fixed truoc ra
--     1.170.000 con bam Percentage truoc ra 1.150.000 - lech 20.000d.
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @org INT=(SELECT OrganizerUserID FROM Concert WHERE ConcertID=@cid);
    DECLARE @u1 INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @t0 DATETIME2(7)=DATEADD(day,-1,SYSDATETIME());
    DECLARE @t1 DATETIME2(7)=DATEADD(day,30,SYSDATETIME());

    -- Hai ghe cung gia de hai booking co cung tam tinh
    DECLARE @s1 INT, @s2 INT, @price DECIMAL(18,0);
    SELECT TOP 2 EventSeatID, SalePrice INTO #g FROM EventSeat
    WHERE ConcertID=@cid AND InventoryStatus=''Available'' ORDER BY SalePrice DESC, EventSeatID;
    IF (SELECT COUNT(*) FROM #g) < 2 THROW 50000,''Thieu ghe trong de chay bai test'',1;
    SELECT @s1=MIN(EventSeatID), @s2=MAX(EventSeatID), @price=MIN(SalePrice) FROM #g;
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID IN (@s1,@s2);

    -- Fixed duoc tao TRUOC -> PromotionID nho hon -> phai dung dau chuoi
    DECLARE @pFix INT, @pPct INT;
    EXEC dbo.sp_CreatePromotion @ActorUserID=@org,@ConcertID=@cid,
         @PromotionName=N''RG18 Fixed200k'',@PromotionDescription=N''regression BR36d'',
         @DiscountType=''Fixed Amount'',@DiscountValue=200000,@StartDatetime=@t0,@EndDatetime=@t1,
         @UsageLimit=NULL,@MaxApplicableQuantity=NULL,@MaxDiscountAmount=NULL,
         @CodeRequiredFlag=0,@NewPromotionID=@pFix OUTPUT;
    EXEC dbo.sp_CreatePromotion @ActorUserID=@org,@ConcertID=@cid,
         @PromotionName=N''RG18 Pct10'',@PromotionDescription=N''regression BR36d'',
         @DiscountType=''Percentage'',@DiscountValue=10,@StartDatetime=@t0,@EndDatetime=@t1,
         @UsageLimit=NULL,@MaxApplicableQuantity=NULL,@MaxDiscountAmount=NULL,
         @CodeRequiredFlag=0,@NewPromotionID=@pPct OUTPUT;

    DECLARE @bA INT, @bB INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u1,@cid,''Pending'',@price,@price,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bA=SCOPE_IDENTITY();
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationTimestamp,AllocationStatus,PriceSnapshot)
    VALUES (@bA,@s1,SYSDATETIME(),''Active'',@price);

    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@u1,@cid,''Pending'',@price,@price,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bB=SCOPE_IDENTITY();
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationTimestamp,AllocationStatus,PriceSnapshot)
    VALUES (@bB,@s2,SYSDATETIME(),''Active'',@price);

    -- A bam dung thu tu tao; B bam nguoc
    EXEC dbo.sp_ApplyPromotion @BookingID=@bA,@PromotionID=@pFix,@DiscountCodeID=NULL,@ActorUserID=@u1;
    EXEC dbo.sp_ApplyPromotion @BookingID=@bA,@PromotionID=@pPct,@DiscountCodeID=NULL,@ActorUserID=@u1;
    EXEC dbo.sp_ApplyPromotion @BookingID=@bB,@PromotionID=@pPct,@DiscountCodeID=NULL,@ActorUserID=@u1;
    EXEC dbo.sp_ApplyPromotion @BookingID=@bB,@PromotionID=@pFix,@DiscountCodeID=NULL,@ActorUserID=@u1;

    DECLARE @fA DECIMAL(18,0)=(SELECT FinalAmount FROM Booking WHERE BookingID=@bA);
    DECLARE @fB DECIMAL(18,0)=(SELECT FinalAmount FROM Booking WHERE BookingID=@bB);

    -- Oracle: tu chay lai chuoi theo dung BR36d/BR36e, doc lap voi sp_ApplyPromotion
    DECLARE @rem DECIMAL(18,0)=@price, @d DECIMAL(18,0);
    SET @d = 200000;                              IF @d > @rem SET @d=@rem; SET @rem=@rem-@d;
    SET @d = CAST(@rem * 10 / 100 AS DECIMAL(18,0)); IF @d > @rem SET @d=@rem; SET @rem=@rem-@d;

    IF @fA <> @fB
        THROW 50000,''BR36d: thu tu khach bam dang quyet dinh gia - hai booking giong het nhau ra hai so tien khac nhau'',1;
    IF @fA <> @rem
        THROW 50000,''BR36d: chuoi khong chay theo thu tu tao Promotion (lech voi ket qua tinh doc lap)'',1;

    -- ApplicationOrder phai bam theo PromotionID tang dan o CA HAI booking
    IF EXISTS (
        SELECT 1
        FROM   BookingPromotionApplication a
        JOIN   BookingPromotionApplication b
               ON b.BookingID = a.BookingID AND b.ApplicationOrder > a.ApplicationOrder
        WHERE  a.BookingID IN (@bA,@bB) AND b.PromotionID < a.PromotionID)
        THROW 50000,''ApplicationOrder khong tang dan theo PromotionID (BR36d/PI06)'',1;

    DROP TABLE #g;';
EXEC test.sp_RunTest @Suite,'Promotion_StackingOrder_FollowsCreationOrder','SUCCESS',NULL,@SQL;

PRINT '== Regression Fix Tests Done ==';
GO
