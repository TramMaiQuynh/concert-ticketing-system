-- ============================================================
-- 04_Test_Triggers_Integrity.sql
-- Test cac trigger toan ven du lieu (BR50-BR53).
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Integrity';
DECLARE @SQL NVARCHAR(MAX);

-- ===== TRG_AuditLog: AuditRecord la bat bien =====
SET @SQL = N'
    UPDATE AuditRecord SET EventType=''MODIFIED'' WHERE 1=0;'; -- empty update -> trigger van ban
-- Test UPDATE tren row that neu co
SET @SQL = N'
    -- Insert 1 audit record truoc
    INSERT INTO AuditRecord (ActorUserID,EventType,EntityType,EntityID,Action,EventTimestamp)
    VALUES (1,''TEST'',''Test'',''1'',''INSERT'',SYSDATETIME());
    DECLARE @id INT = SCOPE_IDENTITY();
    -- Sau do thu UPDATE -> phai bi trigger chan
    UPDATE AuditRecord SET EventType=''MODIFIED'' WHERE AuditID=@id;';
EXEC test.sp_RunTest @Suite,'AuditRecord_Immutable_Update_Fail','ERROR',50100,@SQL;

SET @SQL = N'
    -- Insert 1 audit record truoc
    INSERT INTO AuditRecord (ActorUserID,EventType,EntityType,EntityID,Action,EventTimestamp)
    VALUES (1,''TEST'',''Test'',''1'',''INSERT'',SYSDATETIME());
    DECLARE @id INT = SCOPE_IDENTITY();
    DELETE FROM AuditRecord WHERE AuditID=@id;';
EXEC test.sp_RunTest @Suite,'AuditRecord_Immutable_Delete_Fail','ERROR',50100,@SQL;

-- ===== TRG_TicketConcertConsistency: Ticket.ConcertID != Booking.ConcertID =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    DECLARE @cid2 INT;
    INSERT INTO Concert (OrganizerUserID,VenueID,ConcertName,ConcertStatus,StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused) VALUES (@uid,(SELECT TOP 1 VenueID FROM Venue),''DUMMY'',''Draft'',SYSDATETIME(),DATEADD(d,1,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid2,''TCK_WRONGCID'',''Issued'');';
EXEC test.sp_RunTest @Suite,'Ticket_ConcertID_Mismatch_Fail','ERROR',50012,@SQL;

-- ===== TRG_CheckInConcertConsistency: CheckIn.ConcertID != Ticket.ConcertID =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT, @tid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus) VALUES (@bid,@esid,@cid,''TCK_CHK_TEST'',''Issued'');
    UPDATE Ticket SET TicketStatus=''Used'', UsedTimestamp=SYSDATETIME() WHERE TicketID = SCOPE_IDENTITY();
    SET @tid = SCOPE_IDENTITY();
    DECLARE @cid2 INT;
    INSERT INTO Concert (OrganizerUserID,VenueID,ConcertName,ConcertStatus,StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused) VALUES (@uid,(SELECT TOP 1 VenueID FROM Venue),''DUMMY2'',''Draft'',SYSDATETIME(),DATEADD(d,1,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    INSERT INTO CheckIn (TicketID,ConcertID,CheckInStaffUserID,CheckInTimestamp,ValidationResult)
    VALUES (@tid,@cid2,@staff,SYSDATETIME(),''SUCCESS'');';
EXEC test.sp_RunTest @Suite,'CheckIn_ConcertID_Mismatch_Fail','ERROR',50013,@SQL;

-- ===== TRG_InventoryAllocationConsistency: Active Alloc tren ghe Available =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    -- Ghe van la Available nhung insert Active Allocation -> phai loi
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid,''Active'',1000000);';
EXEC test.sp_RunTest @Suite,'Allocation_Active_on_Available_Seat_Fail','ERROR',50030,@SQL;

-- ===== TRG_OneActiveTicketPerEventSeat: 2 ticket Issued cho cung ghe =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid1 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid1 INT, @bid2 INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid1,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid1 = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid2,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid2 = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid1,@esid,''Released'',1000000);
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid2,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid1,@esid,@cid,''TCK_DUP_1'',''Issued'');
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid2,@esid,@cid,''TCK_DUP_2'',''Issued'');';
EXEC test.sp_RunTest @Suite,'OneActiveTicket_DupIssued_Fail','ERROR',2601,@SQL;

-- ===== TRG_PaymentEffectiveSingle: 2 Payment IsBookingConfirmingPayment=1 cho 1 Booking =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
    SET @bid = SCOPE_IDENTITY();
    UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID=@bid;
    -- INSERT payment 1 voi ref khac nhau va IsBookingConfirmingPayment=1
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-EFF-1'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-EFF-1'';
    -- INSERT payment 2 cung IsBookingConfirmingPayment=1 -> TRG_PaymentEffectiveSingle phai chan
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference,IsBookingConfirmingPayment)
    VALUES (@bid,''Pending'',1000000,''REF-EFF-2'',1);
    UPDATE Payment SET PaymentStatus=''Confirmed'', ConfirmationTimestamp=SYSDATETIME() WHERE BookingID=@bid AND PaymentReference=''REF-EFF-2'';';
EXEC test.sp_RunTest @Suite,'PaymentEffective_Duplicate_Fail50070','ERROR',2601,@SQL;

-- ===== TRG_RefundLimits: Refund vuot qua Payment.Amount =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
UPDATE Booking SET BookingStatus=''Confirmed'', ConfirmedTimestamp=SYSDATETIME(), HoldStartDatetime=NULL, HoldExpiryDatetime=NULL WHERE BookingID = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Confirmed'',500000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',300000);
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',300000);';
EXEC test.sp_RunTest @Suite,'RefundLimits_ExceedPaymentAmount_Fail','ERROR',NULL,@SQL;

-- ===== TRG_ConcertVenueChangeGuard: doi VenueID Concert khi da co EventSeat -> 50130 =====
SET @SQL = N'
    DECLARE @vid2 INT;
    INSERT INTO Venue (VenueName,Address,VenueStatus) VALUES (''Guard Venue C'',''Addr'',''Active'');
    SET @vid2 = SCOPE_IDENTITY();
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE EXISTS (SELECT 1 FROM EventSeat WHERE ConcertID = Concert.ConcertID) ORDER BY ConcertID);
    UPDATE Concert SET VenueID = @vid2 WHERE ConcertID = @cid;';
EXEC test.sp_RunTest @Suite,'ConcertVenueChangeGuard_Fail','ERROR',50130,@SQL;

-- ===== TRG_SeatVenueChangeGuard: doi VenueID Seat khi da co EventSeat -> 50131 =====
SET @SQL = N'
    DECLARE @vid2 INT;
    INSERT INTO Venue (VenueName,Address,VenueStatus) VALUES (''Guard Venue S'',''Addr'',''Active'');
    SET @vid2 = SCOPE_IDENTITY();
    DECLARE @sid INT = (SELECT TOP 1 SeatID FROM Seat WHERE EXISTS (SELECT 1 FROM EventSeat WHERE SeatID = Seat.SeatID) ORDER BY SeatID);
    UPDATE Seat SET VenueID = @vid2 WHERE SeatID = @sid;';
-- 50131 chu khong phai 50120: doi VenueID cua Seat dang duoc EventSeat tham chieu la
-- dung pham vi cua TRG_SeatVenueChangeGuard. Ca hai trigger deu tu choi lenh nay, nen
-- thu tu kich hoat da duoc ghim tuong minh (sp_settriggerorder, xem file trigger) -
-- neu khong, ma loi tra ve se khong xac dinh giua hai lan chay.
EXEC test.sp_RunTest @Suite,'SeatVenueChangeGuard_Fail','ERROR',50131,@SQL;

-- ===== TRG_EventSeatVenue (UPDATE): doi EventSeat sang concert khac venue -> 50020 =====
SET @SQL = N'
    DECLARE @vid2 INT;
    INSERT INTO Venue (VenueName,Address,VenueStatus) VALUES (''Guard Venue ES'',''Addr'',''Active'');
    SET @vid2 = SCOPE_IDENTITY();
    DECLARE @cat2 INT;
    INSERT INTO TicketCategory (ConcertID,CategoryName,BasePrice,CategoryStatus) VALUES ((SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID),''GuardCat'',100000,''Active'');
    INSERT INTO TicketCategory (ConcertID,CategoryName,BasePrice,CategoryStatus) VALUES ((SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID),''GuardCat2'',100000,''Active'');
    -- Tao concert moi o venue moi
    DECLARE @cid2 INT;
    INSERT INTO Concert (OrganizerUserID,VenueID,ConcertName,ConcertStatus,StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES ((SELECT UserID FROM UserAccount WHERE Username=''test_org''),@vid2,''Guard Concert'',''Draft'',SYSDATETIME(),DATEADD(d,1,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    DECLARE @cat3 INT;
    INSERT INTO TicketCategory (ConcertID,CategoryName,BasePrice,CategoryStatus) VALUES (@cid2,''GuardCat3'',100000,''Active'');
    SET @cat3 = SCOPE_IDENTITY();
    DECLARE @es INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID) ORDER BY EventSeatID);
    UPDATE EventSeat SET ConcertID = @cid2, TicketCategoryID = @cat3 WHERE EventSeatID = @es;';
EXEC test.sp_RunTest @Suite,'EventSeatVenue_UpdateConcert_Fail','ERROR',50020,@SQL;

-- ===== FK_BPA_DiscountCode (composite): code thuoc promotion khac -> loi FK =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    -- Promotion 1 co code
    DECLARE @p1 INT, @code1 INT;
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,StartDatetime,EndDatetime,PromotionStatus,CodeRequiredFlag,UsageLimit)
    VALUES (@cid,''Composite P1'',''Fixed Amount'',10000,SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),''Active'',1,100);
    SET @p1 = SCOPE_IDENTITY();
    INSERT INTO DiscountCode (PromotionID,CodeValue,ValidFromDatetime,ValidToDatetime,CodeStatus)
    VALUES (@p1,''CP1'',SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),''Active'');
    SET @code1 = SCOPE_IDENTITY();
    -- Promotion 2 khong code
    DECLARE @p2 INT;
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,StartDatetime,EndDatetime,PromotionStatus,CodeRequiredFlag,UsageLimit)
    VALUES (@cid,''Composite P2'',''Fixed Amount'',10000,SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),''Active'',0,100);
    SET @p2 = SCOPE_IDENTITY();
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime) VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute, 15, SYSDATETIME()));
SET @bid = SCOPE_IDENTITY();
    -- Dung code cua P1 nhung bo vao P2 -> FK composite phai chan (xem chu thich duoi).
    INSERT INTO BookingPromotionApplication (BookingID,PromotionID,DiscountCodeID,ApplicationOrder,DiscountAmount,AppliedTimestamp)
    VALUES (@bid,@p2,@code1,1,5000,SYSDATETIME());';
-- ApplicationOrder la BAT BUOC (NOT NULL, khong co DEFAULT). Ban truoc cua bai test
-- nay bo quen cot do, nen INSERT chet o loi 515 (Cannot insert the value NULL) TRUOC
-- khi SQL Server kip xet khoa ngoai; va vi ky vong chi ghi ERROR chung chung nen test
-- van PASS trong khi FK_BPA_DiscountCode chua he duoc cham toi. Nay dien du cot VA
-- khang dinh dung ma loi 547 - neu khoa ngoai bien mat, test se that bai thay vi im lang.
EXEC test.sp_RunTest @Suite,'BPA_CompositeFK_WrongPromotion_Fail','ERROR',547,@SQL;

-- ===== TRG_EventSeat_AllocationConsistency: doi InventoryStatus khi co Active Alloc =====
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT=(SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'' AND ConcertID=@cid ORDER BY EventSeatID);
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    -- Setup: set OnHold + Active Alloc (bypass TRG_InventoryAllocationConsistency)
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid,''Active'',1000000);
    -- Gio thu doi InventoryStatus -> Available khi van con Active Alloc -> phai loi 50031
    UPDATE EventSeat SET InventoryStatus=''Available'' WHERE EventSeatID=@esid;';
EXEC test.sp_RunTest @Suite,'EventSeatAllocationConsistency_ActiveAllocPreventStatusChange_Fail50031','ERROR',50031,@SQL;

-- ===== TRG_EventSeat_PriceInsert: INSERT EventSeat voi SalePrice != BasePrice =====
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @catid INT=(SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid);
    DECLARE @baseprice DECIMAL(18,0)=(SELECT BasePrice FROM TicketCategory WHERE TicketCategoryID=@catid AND ConcertID=@cid);
    DECLARE @zoneid INT=(SELECT TOP 1 ZoneID FROM Zone);
    DECLARE @venueid INT=(SELECT VenueID FROM Zone WHERE ZoneID=@zoneid);
    INSERT INTO Seat (ZoneID,VenueID,SeatCode,SeatLabel) VALUES (@zoneid,@venueid,''Z-99'',''Z-99'');
    DECLARE @sid INT=SCOPE_IDENTITY();
    -- INSERT voi SalePrice khac BasePrice -> phai loi 50060
    INSERT INTO EventSeat (ConcertID,SeatID,TicketCategoryID,InventoryStatus,SalePrice)
    VALUES (@cid,@sid,@catid,''Available'',@baseprice + 1);';
EXEC test.sp_RunTest @Suite,'EventSeat_PriceInsert_WrongPrice_Fail50061','ERROR',50061,@SQL;

-- ===== TRG_Booking_DiscountUsageGuard: Pending->Expired giam ReservedUsageCount =====
SET @SQL = N'
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT=(SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @pid INT=(SELECT TOP 1 PromotionID FROM Promotion WHERE ConcertID=@cid);
    DECLARE @dcid INT=(SELECT TOP 1 DiscountCodeID FROM DiscountCode WHERE PromotionID=@pid AND CodeStatus=''Active'');
    DECLARE @bid INT;
    DECLARE @reserved_before INT=(SELECT ReservedUsageCount FROM DiscountCode WHERE DiscountCodeID=@dcid);
    -- Apply promotion to booking
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount,HoldStartDatetime,HoldExpiryDatetime)
    VALUES (@uid,@cid,''Pending'',1000000,1000000,SYSDATETIME(),DATEADD(minute,15,SYSDATETIME()));
    SET @bid=SCOPE_IDENTITY();
    INSERT INTO BookingPromotionApplication (BookingID,PromotionID,DiscountCodeID,DiscountAmount,AppliedTimestamp,ApplicationOrder)
    VALUES (@bid,@pid,@dcid,200000,SYSDATETIME(),1);
    -- Tang Reserved thu cong (nhu sp_ApplyPromotion lam)
    UPDATE DiscountCode SET ReservedUsageCount=ReservedUsageCount+1 WHERE DiscountCodeID=@dcid;
    DECLARE @reserved_mid INT=(SELECT ReservedUsageCount FROM DiscountCode WHERE DiscountCodeID=@dcid);
    -- Cancel booking -> trigger phai giam ReservedUsageCount
    UPDATE Booking SET BookingStatus=''Expired'', ExpiredTimestamp=SYSDATETIME() WHERE BookingID=@bid;
    DECLARE @reserved_after INT=(SELECT ReservedUsageCount FROM DiscountCode WHERE DiscountCodeID=@dcid);
    IF @reserved_after <> @reserved_before
        THROW 50000,''ReservedUsageCount phai tra lai ve gia tri ban dau sau Expired'',1;';
EXEC test.sp_RunTest @Suite,'DiscountUsageGuard_ExpiredBooking_ReducesReserved','SUCCESS',NULL,@SQL;

PRINT '== Integrity Tests Done ==';
GO


