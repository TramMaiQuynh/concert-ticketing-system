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
EXEC sp_RunTest @Suite,'AuditRecord_Immutable_Update_Fail','ERROR',50100,@SQL;

SET @SQL = N'
    -- Insert 1 audit record truoc
    INSERT INTO AuditRecord (ActorUserID,EventType,EntityType,EntityID,Action,EventTimestamp)
    VALUES (1,''TEST'',''Test'',''1'',''INSERT'',SYSDATETIME());
    DECLARE @id INT = SCOPE_IDENTITY();
    DELETE FROM AuditRecord WHERE AuditID=@id;';
EXEC sp_RunTest @Suite,'AuditRecord_Immutable_Delete_Fail','ERROR',50100,@SQL;

-- ===== TRG_TicketConcertConsistency: Ticket.ConcertID != Booking.ConcertID =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Confirmed'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    DECLARE @cid2 INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused) VALUES (@uid,(SELECT TOP 1 ArtistID FROM Artist),(SELECT TOP 1 VenueID FROM Venue),''DUMMY'',''Draft'',SYSDATETIME(),DATEADD(d,1,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid2,''TCK_WRONGCID'',''Issued'');';
EXEC sp_RunTest @Suite,'Ticket_ConcertID_Mismatch_Fail','ERROR',50012,@SQL;

-- ===== TRG_CheckInConcertConsistency: CheckIn.ConcertID != Ticket.ConcertID =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT, @tid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Confirmed'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid,''TCK_CHK_TEST'',''Used'');
    SET @tid = SCOPE_IDENTITY();
    DECLARE @cid2 INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused) VALUES (@uid,(SELECT TOP 1 ArtistID FROM Artist),(SELECT TOP 1 VenueID FROM Venue),''DUMMY2'',''Draft'',SYSDATETIME(),DATEADD(d,1,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    INSERT INTO CheckIn (TicketID,ConcertID,CheckInStaffUserID,CheckInTimestamp,ValidationResult)
    VALUES (@tid,@cid2,@staff,SYSDATETIME(),''SUCCESS'');';
EXEC sp_RunTest @Suite,'CheckIn_ConcertID_Mismatch_Fail','ERROR',50013,@SQL;

-- ===== TRG_InventoryAllocationConsistency: Active Alloc tren ghe Available =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    -- Ghe van la Available nhung insert Active Allocation -> phai loi
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot)
    VALUES (@bid,@esid,''Active'',1000000);';
EXEC sp_RunTest @Suite,'Allocation_Active_on_Available_Seat_Fail','ERROR',50030,@SQL;

-- ===== TRG_OneActiveTicketPerEventSeat: 2 ticket Issued cho cung ghe =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid1 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid1 INT, @bid2 INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid1,@cid,''Confirmed'',1000000,1000000);
    SET @bid1 = SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid2,@cid,''Confirmed'',1000000,1000000);
    SET @bid2 = SCOPE_IDENTITY();
    UPDATE EventSeat SET InventoryStatus=''OnHold'' WHERE EventSeatID=@esid;
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid1,@esid,''Released'',1000000);
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus,PriceSnapshot) VALUES (@bid2,@esid,''Active'',1000000);
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid1,@esid,@cid,''TCK_DUP_1'',''Issued'');
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid2,@esid,@cid,''TCK_DUP_2'',''Issued'');';
EXEC sp_RunTest @Suite,'OneActiveTicket_DupIssued_Fail','ERROR',50050,@SQL;

-- ===== TRG_PaymentConfirmedSingle: 2 Payment Confirmed cho 1 Booking =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,FinalAmount)
    VALUES (@uid,@cid,''Confirmed'',1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Confirmed'',1000000,''REF-TEST'');
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Confirmed'',1000000,''REF-TEST'');';
EXEC sp_RunTest @Suite,'PaymentConfirmed_Duplicate_Fail','ERROR',NULL,@SQL;

-- ===== TRG_RefundLimits: Refund vuot qua Payment.Amount =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Confirmed'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount,PaymentReference) VALUES (@bid,''Confirmed'',500000,''REF-TEST'');
    SET @pid = SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',300000);
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',300000);';
EXEC sp_RunTest @Suite,'RefundLimits_ExceedPaymentAmount_Fail','ERROR',NULL,@SQL;

-- ===== TRG_ConcertVenueChangeGuard: doi VenueID Concert khi da co EventSeat -> 50130 =====
SET @SQL = N'
    DECLARE @vid2 INT;
    INSERT INTO Venue (VenueName,Address,VenueStatus) VALUES (''Guard Venue C'',''Addr'',''Active'');
    SET @vid2 = SCOPE_IDENTITY();
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE EXISTS (SELECT 1 FROM EventSeat WHERE ConcertID = Concert.ConcertID) ORDER BY ConcertID);
    UPDATE Concert SET VenueID = @vid2 WHERE ConcertID = @cid;';
EXEC sp_RunTest @Suite,'ConcertVenueChangeGuard_Fail','ERROR',50130,@SQL;

-- ===== TRG_SeatVenueChangeGuard: doi VenueID Seat khi da co EventSeat -> 50131 =====
SET @SQL = N'
    DECLARE @vid2 INT;
    INSERT INTO Venue (VenueName,Address,VenueStatus) VALUES (''Guard Venue S'',''Addr'',''Active'');
    SET @vid2 = SCOPE_IDENTITY();
    DECLARE @sid INT = (SELECT TOP 1 SeatID FROM Seat WHERE EXISTS (SELECT 1 FROM EventSeat WHERE SeatID = Seat.SeatID) ORDER BY SeatID);
    UPDATE Seat SET VenueID = @vid2 WHERE SeatID = @sid;';
EXEC sp_RunTest @Suite,'SeatVenueChangeGuard_Fail','ERROR',50131,@SQL;

-- ===== TRG_EventSeatVenue (UPDATE): doi EventSeat sang concert khac venue -> 50020 =====
SET @SQL = N'
    DECLARE @vid2 INT;
    INSERT INTO Venue (VenueName,Address,VenueStatus) VALUES (''Guard Venue ES'',''Addr'',''Active'');
    SET @vid2 = SCOPE_IDENTITY();
    DECLARE @cat2 INT;
    INSERT INTO TicketCategory (ConcertID,CategoryName,CategoryStatus) VALUES ((SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID),''GuardCat'',''Active'');
    INSERT INTO TicketCategory (ConcertID,CategoryName,CategoryStatus) VALUES ((SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID),''GuardCat2'',''Active'');
    -- Tao concert moi o venue moi
    DECLARE @cid2 INT;
    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,StartDatetime,EndDatetime,PurchaseLimit,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES ((SELECT UserID FROM UserAccount WHERE Username=''test_org''),(SELECT TOP 1 ArtistID FROM Artist),@vid2,''Guard Concert'',''Draft'',SYSDATETIME(),DATEADD(d,1,SYSDATETIME()),4,0,0,0);
    SET @cid2 = SCOPE_IDENTITY();
    DECLARE @cat3 INT;
    INSERT INTO TicketCategory (ConcertID,CategoryName,CategoryStatus) VALUES (@cid2,''GuardCat3'',''Active'');
    SET @cat3 = SCOPE_IDENTITY();
    DECLARE @es INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID) ORDER BY EventSeatID);
    UPDATE EventSeat SET ConcertID = @cid2, TicketCategoryID = @cat3 WHERE EventSeatID = @es;';
EXEC sp_RunTest @Suite,'EventSeatVenue_UpdateConcert_Fail','ERROR',50020,@SQL;

-- ===== FK_BPA_DiscountCode (composite): code thuoc promotion khac -> loi FK =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    -- Promotion 1 co code
    DECLARE @p1 INT, @code1 INT;
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,StartDatetime,EndDatetime,PromotionStatus,CodeRequiredFlag,UsageLimit)
    VALUES (@cid,''Composite P1'',''FIXED'',10000,SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),''Active'',1,100);
    SET @p1 = SCOPE_IDENTITY();
    INSERT INTO DiscountCode (PromotionID,CodeValue,ValidFromDatetime,ValidToDatetime,CodeStatus)
    VALUES (@p1,''CP1'',SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),''Active'');
    SET @code1 = SCOPE_IDENTITY();
    -- Promotion 2 khong code
    DECLARE @p2 INT;
    INSERT INTO Promotion (ConcertID,PromotionName,DiscountType,DiscountValue,StartDatetime,EndDatetime,PromotionStatus,CodeRequiredFlag,UsageLimit)
    VALUES (@cid,''Composite P2'',''FIXED'',10000,SYSDATETIME(),DATEADD(d,10,SYSDATETIME()),''Active'',0,100);
    SET @p2 = SCOPE_IDENTITY();
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,''Pending'',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    -- Dung code cua P1 nhung bo vao P2 -> FK composite phai chan
    INSERT INTO BookingPromotionApplication (BookingID,PromotionID,DiscountCodeID,DiscountAmount,AppliedTimestamp)
    VALUES (@bid,@p2,@code1,5000,SYSDATETIME());';
EXEC sp_RunTest @Suite,'BPA_CompositeFK_WrongPromotion_Fail','ERROR',NULL,@SQL;

PRINT '== Integrity Tests Done ==';
GO


