-- ============================================================
-- sp_UpdateConcertStatus (BP1/BP4 / FR16 / BR49)
-- Chuyen trang thai Concert theo state machine.
-- Cac chuyen doi hop le duoc stip boi TRG_Concert_StateTransition;
-- SP chi kiem tra quyen truoc khi UPDATE.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateConcertStatus
(
    @ConcertID   INT,
    @ActorUserID INT,
    @NewStatus   VARCHAR(32)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @NewStatus NOT IN ('Draft','Published','OnSale','SaleClosed','Completed','Cancelled')
            THROW 58020, 'sp_UpdateConcertStatus: ConcertStatus khong hop le.', 1;

        DECLARE @OrganizerUserID INT, @CurrentStatus VARCHAR(32);
        SELECT @OrganizerUserID = OrganizerUserID, @CurrentStatus = ConcertStatus
        FROM Concert WHERE ConcertID = @ConcertID;

        IF @CurrentStatus IS NULL
            THROW 58021, 'sp_UpdateConcertStatus: Concert khong ton tai.', 1;

        -- Quyen: Organizer cua Concert hoac Admin
        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 58022, 'sp_UpdateConcertStatus: Actor khong co quyen.', 1;

        -- BR10 (§12.5.1 dong 460): Concert KHONG duoc chuyen sang OnSale
        -- khi ticket inventory (EventSeat) va sale configuration (SaleStart/SaleEnd)
        -- chua duoc xac dinh day du.
        IF @NewStatus = 'OnSale'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM EventSeat WHERE ConcertID = @ConcertID)
                THROW 58023, 'sp_UpdateConcertStatus (BR10): Concert chua co EventSeat (ticket inventory) - khong the mo ban.', 1;

            DECLARE @SaleStart DATETIME2(7), @SaleEnd DATETIME2(7);
            SELECT @SaleStart = SaleStartDatetime, @SaleEnd = SaleEndDatetime
            FROM   Concert WHERE ConcertID = @ConcertID;

            IF @SaleStart IS NULL OR @SaleEnd IS NULL
                THROW 58024, 'sp_UpdateConcertStatus (BR10): Concert chua cau hinh SaleStartDatetime/SaleEndDatetime - khong the mo ban.', 1;
        END

        -- =================================================================
        -- SIP4 / BR34: Cascade Cancellation
        -- =================================================================
        IF @NewStatus = 'Cancelled'
        BEGIN
            -- 1. Tao Refund cho phan chua hoan cua cac Payment dang Confirmed/PartiallyRefunded (CRIT-07, I-12)
            INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason)
            SELECT p.PaymentID, 
                   p.Amount - ISNULL((SELECT SUM(RefundAmount) FROM Refund r WHERE r.PaymentID = p.PaymentID AND r.RefundStatus = 'Confirmed'), 0),
                   'Pending', SYSDATETIME(), 'Concert Cancelled'
            FROM Payment p
            JOIN Booking b ON b.BookingID = p.BookingID
            WHERE b.ConcertID = @ConcertID AND b.BookingStatus = 'Confirmed' 
              AND p.IsBookingConfirmingPayment = 1 AND p.PaymentStatus IN ('Confirmed', 'PartiallyRefunded')
              AND p.Amount > ISNULL((SELECT SUM(RefundAmount) FROM Refund r2 WHERE r2.PaymentID = p.PaymentID AND r2.RefundStatus = 'Confirmed'), 0);

            -- 2. Cap nhat Payment -> Refunded
            UPDATE p
            SET PaymentStatus = 'Refunded'
            FROM Payment p
            JOIN Booking b ON b.BookingID = p.BookingID
            WHERE b.ConcertID = @ConcertID AND b.BookingStatus = 'Confirmed' 
              AND p.IsBookingConfirmingPayment = 1 AND p.PaymentStatus IN ('Confirmed', 'PartiallyRefunded');

            -- 3. Chuyen tat ca Booking Pending/Confirmed -> Cancelled
            UPDATE Booking 
            SET BookingStatus = 'Cancelled' 
            WHERE ConcertID = @ConcertID AND BookingStatus IN ('Pending', 'Confirmed');

            -- 4. Chuyen tat ca Ticket Issued -> Cancelled
            UPDATE Ticket 
            SET TicketStatus = 'Cancelled' 
            WHERE ConcertID = @ConcertID AND TicketStatus = 'Issued';

            -- 5. Giai phong EventSeat
            UPDATE EventSeat 
            SET InventoryStatus = 'Available' 
            WHERE ConcertID = @ConcertID AND InventoryStatus IN ('OnHold', 'OnHoldForWaitlist', 'Booked');

            -- 6. Giai phong Booking Allocation
            UPDATE a
            SET AllocationStatus = 'Released', ReleaseTimestamp = SYSDATETIME()
            FROM BookingEventSeatAllocation a
            JOIN Booking b ON b.BookingID = a.BookingID
            WHERE b.ConcertID = @ConcertID AND a.AllocationStatus = 'Active';

            -- 7. WaitlistEntry Active/Granted -> Cancelled
            UPDATE e
            SET EntryStatus = 'Cancelled'
            FROM WaitlistEntry e
            JOIN Waitlist w ON w.WaitlistID = e.WaitlistID
            WHERE w.ConcertID = @ConcertID AND e.EntryStatus IN ('Active', 'Granted');

            -- 8. Giai phong Waitlist Allocation
            UPDATE a
            SET AllocationStatus = 'Released', ReleaseTimestamp = SYSDATETIME()
            FROM WaitlistEntryEventSeatAllocation a
            JOIN WaitlistEntry e ON e.WaitlistEntryID = a.WaitlistEntryID
            JOIN Waitlist w ON w.WaitlistID = e.WaitlistID
            WHERE w.ConcertID = @ConcertID AND a.AllocationStatus = 'Active';

            -- 9. Dong Waitlist
            UPDATE Waitlist 
            SET WaitlistStatus = 'Closed' 
            WHERE ConcertID = @ConcertID AND WaitlistStatus = 'Open';

            -- 10. QueueEntry Waiting/Admitted -> Cancelled (CRIT-03)
            UPDATE e
            SET QueueStatus = 'Cancelled', ExitTimestamp = SYSDATETIME()
            FROM QueueEntry e
            JOIN Queue q ON q.QueueID = e.QueueID
            WHERE q.ConcertID = @ConcertID AND e.QueueStatus IN ('Waiting', 'Admitted');

            -- 11. Dong Queue
            UPDATE Queue 
            SET QueueStatus = 'Closed' 
            WHERE ConcertID = @ConcertID AND QueueStatus = 'Open';

            -- Audit Tong hop
            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'CONCERT_CASCADE_CANCELLED', 'Concert', CAST(@ConcertID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"Reason":"Concert Cancelled SIP4"}');
        END

        -- UPDATE -> TRG_Concert_StateTransition tu chan chuyen doi khong hop le
        UPDATE Concert SET ConcertStatus = @NewStatus WHERE ConcertID = @ConcertID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'CONCERT_STATUS_CHANGED', 'Concert',
                CAST(@ConcertID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"ConcertStatus":"' + @CurrentStatus + '"}',
                '{"ConcertStatus":"' + @NewStatus + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO