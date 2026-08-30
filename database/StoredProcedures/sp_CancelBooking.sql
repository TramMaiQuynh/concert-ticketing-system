-- ============================================================
-- sp_CancelBooking 
-- Huy Booking, nha ghe (EventSeat) va huy phan bo (Allocation).
-- ============================================================
CREATE PROCEDURE dbo.sp_CancelBooking
(
    @BookingID      INT,
    @CustomerUserID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Kiem tra Booking hop le
        DECLARE @BookingStatus VARCHAR(32);
        
        SELECT @BookingStatus = BookingStatus
        FROM   Booking WITH (UPDLOCK)
        WHERE  BookingID = @BookingID
          AND  CustomerUserID = @CustomerUserID;

        IF @BookingStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 55001, 'sp_CancelBooking: Booking khong ton tai hoac khong thuoc ve ban.', 1;
        END

        IF @BookingStatus <> 'Pending'
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 55002, 'sp_CancelBooking: Chi the huy Booking o trang thai Pending.', 1;
        END

        -- 2. Cap nhat Booking -> Cancelled
        UPDATE Booking
        SET    BookingStatus = 'Cancelled', 
               CancelledTimestamp = SYSDATETIME()
        WHERE  BookingID = @BookingID;

        -- 3. Cap nhat BookingEventSeatAllocation -> Released
        UPDATE BookingEventSeatAllocation
        SET    AllocationStatus = 'Released', 
               ReleaseTimestamp = SYSDATETIME()
        WHERE  BookingID = @BookingID;

        -- 4. Cap nhat EventSeat -> Available
        UPDATE EventSeat
        SET    InventoryStatus = 'Available'
        WHERE  EventSeatID IN (
            SELECT EventSeatID 
            FROM   BookingEventSeatAllocation 
            WHERE  BookingID = @BookingID
        );

        -- 5. Ghi AuditRecord
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@CustomerUserID, 'BOOKING_CANCELLED', 'Booking',
             CAST(@BookingID AS VARCHAR(64)), 'UPDATE',
             SYSDATETIME(),
             '{"BookingStatus":"Cancelled"}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
