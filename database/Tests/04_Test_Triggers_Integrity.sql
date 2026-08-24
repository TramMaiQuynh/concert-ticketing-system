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
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Confirmed',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    -- Dung ConcertID sai (cid+1 khong ton tai hoac sai)
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid+9999,''TCK_WRONGCID'',''Issued'');';
EXEC sp_RunTest @Suite,'Ticket_ConcertID_Mismatch_Fail','ERROR',50010,@SQL;

-- ===== TRG_CheckInConcertConsistency: CheckIn.ConcertID != Ticket.ConcertID =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @staff INT = (SELECT UserID FROM UserAccount WHERE Username=''test_staff'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT, @tid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Confirmed',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Ticket (BookingID,EventSeatID,ConcertID,TicketCode,TicketStatus)
    VALUES (@bid,@esid,@cid,''TCK_CHK_TEST'',''Used'');
    SET @tid = SCOPE_IDENTITY();
    INSERT INTO CheckIn (TicketID,ConcertID,CheckInStaffUserID,CheckInTimestamp,ValidationResult)
    VALUES (@tid,@cid+9999,@staff,SYSDATETIME(),''SUCCESS'');';
EXEC sp_RunTest @Suite,'CheckIn_ConcertID_Mismatch_Fail','ERROR',50011,@SQL;

-- ===== TRG_InventoryAllocationConsistency: Active Alloc tren ghe Available =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Pending',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    -- Ghe van la Available nhung insert Active Allocation -> phai loi
    INSERT INTO BookingEventSeatAllocation (BookingID,EventSeatID,AllocationStatus)
    VALUES (@bid,@esid,''Active'');';
EXEC sp_RunTest @Suite,'Allocation_Active_on_Available_Seat_Fail','ERROR',50030,@SQL;

-- ===== TRG_OneActiveTicketPerEventSeat: 2 ticket Issued cho cung ghe =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid1 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @uid2 INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    DECLARE @esid INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE InventoryStatus=''Available'');
    DECLARE @bid1 INT, @bid2 INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid1,@cid,'Confirmed',1000000,1000000);
    SET @bid1 = SCOPE_IDENTITY();
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid2,@cid,'Confirmed',1000000,1000000);
    SET @bid2 = SCOPE_IDENTITY();
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
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''Confirmed'',1000000);
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''Confirmed'',1000000);';
EXEC sp_RunTest @Suite,'PaymentConfirmed_Duplicate_Fail','ERROR',NULL,@SQL;

-- ===== TRG_RefundLimits: Refund vuot qua Payment.Amount =====
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @bid INT, @pid INT;
    INSERT INTO Booking (CustomerUserID,ConcertID,BookingStatus,SubtotalAmount,FinalAmount) VALUES (@uid,@cid,'Confirmed',1000000,1000000);
    SET @bid = SCOPE_IDENTITY();
    INSERT INTO Payment (BookingID,PaymentStatus,Amount) VALUES (@bid,''Confirmed'',500000);
    SET @pid = SCOPE_IDENTITY();
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',300000);
    INSERT INTO Refund (PaymentID,RefundStatus,RefundAmount) VALUES (@pid,''Pending'',300000);';
EXEC sp_RunTest @Suite,'RefundLimits_ExceedPaymentAmount_Fail','ERROR',NULL,@SQL;

PRINT '== Integrity Tests Done ==';
GO


