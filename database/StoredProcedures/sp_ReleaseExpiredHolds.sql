-- ============================================================
-- sp_ReleaseExpiredHolds (BP7 / SIP1 / BR18-BR19)
-- Tien trinh tu dong: tim va giai phong tat ca Booking Pending
-- da qua han HoldExpiryDatetime ma chua thanh toan.
-- Duoc goi dinh ky boi SQL Agent Job (SIP1).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ReleaseExpiredHolds
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID INT;
    SELECT  @SystemUserID = UserID FROM UserAccount WHERE Username = 'system';

    DECLARE @Now DATETIME2(7) = SYSDATETIME();

    -- Tim cac Booking can xu ly
    CREATE TABLE #ExpiredBookings (BookingID INT NOT NULL);
    INSERT INTO #ExpiredBookings (BookingID)
    SELECT BookingID
    FROM   Booking
    WHERE  BookingStatus      = 'Pending'
      AND  HoldExpiryDatetime < @Now;

    IF NOT EXISTS (SELECT 1 FROM #ExpiredBookings)
    BEGIN
        DROP TABLE #ExpiredBookings;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Chuyen Booking -> Expired
        UPDATE Booking
        SET    BookingStatus     = 'Expired',
               ExpiredTimestamp  = @Now
        WHERE  BookingID IN (SELECT BookingID FROM #ExpiredBookings);

        -- 2. Chuyen Allocation -> Released
        UPDATE BookingEventSeatAllocation
        SET    AllocationStatus  = 'Released',
               ReleaseTimestamp  = @Now
        WHERE  BookingID         IN (SELECT BookingID FROM #ExpiredBookings)
          AND  AllocationStatus  = 'Active';

        -- 3. Tra lai EventSeat -> Available
        UPDATE EventSeat
        SET    InventoryStatus = 'Available'
        WHERE  EventSeatID IN (
                   SELECT DISTINCT besa.EventSeatID
                   FROM   BookingEventSeatAllocation besa
                   JOIN   #ExpiredBookings eb ON eb.BookingID = besa.BookingID
               )
          AND  InventoryStatus = 'OnHold';

        -- 4. Ghi AuditRecord cho moi Booking het han
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        SELECT @SystemUserID,
               'SYSTEM_HOLD_EXPIRED',
               'Booking',
               CAST(BookingID AS VARCHAR(64)),
               'UPDATE',
               @Now,
               '{"BookingStatus":"Expired"}'
        FROM   #ExpiredBookings;

        DROP TABLE #ExpiredBookings;
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#ExpiredBookings') IS NOT NULL DROP TABLE #ExpiredBookings;
        THROW;
    END CATCH
END;
GO
