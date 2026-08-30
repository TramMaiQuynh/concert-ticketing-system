-- ============================================================
-- sp_ReleaseExpiredHolds (BP7 / SIP1 / BR18-BR19)
-- Tien trinh tu dong: tim va giai phong tat ca Booking Pending
-- da qua han HoldExpiryDatetime ma chua thanh toan.
-- Duoc goi dinh ky boi SQL Agent Job (SIP1).
-- ============================================================
CREATE PROCEDURE dbo.sp_ReleaseExpiredHolds
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

    -- Tim cac WaitlistEntry can xu ly
    CREATE TABLE #ExpiredWaitlist (WaitlistEntryID INT NOT NULL, OfferedEventSeatID INT NOT NULL);
    INSERT INTO #ExpiredWaitlist (WaitlistEntryID, OfferedEventSeatID)
    SELECT WaitlistEntryID, OfferedEventSeatID
    FROM   WaitlistEntry
    WHERE  EntryStatus = 'Granted'
      AND  OpportunityExpiryTimestamp < @Now
      AND  OfferedEventSeatID IS NOT NULL;

    DECLARE @HasBookings BIT = CASE WHEN EXISTS (SELECT 1 FROM #ExpiredBookings) THEN 1 ELSE 0 END;
    DECLARE @HasWaitlists BIT = CASE WHEN EXISTS (SELECT 1 FROM #ExpiredWaitlist) THEN 1 ELSE 0 END;

    IF @HasBookings = 0 AND @HasWaitlists = 0
    BEGIN
        DROP TABLE #ExpiredBookings;
        DROP TABLE #ExpiredWaitlist;
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @HasBookings = 1
        BEGIN
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
        END

        IF @HasWaitlists = 1
        BEGIN
            -- 5. Tim va giai phong co hoi Waitlist het han
            UPDATE WaitlistEntry
            SET    EntryStatus = 'Expired'
            WHERE  WaitlistEntryID IN (SELECT WaitlistEntryID FROM #ExpiredWaitlist)
              AND  EntryStatus = 'Granted';  -- conditional

            -- 6. Tra lai EventSeat -> Available
            UPDATE EventSeat
            SET    InventoryStatus = 'Available'
            WHERE  EventSeatID IN (SELECT OfferedEventSeatID FROM #ExpiredWaitlist)
              AND  InventoryStatus = 'OnHoldForWaitlist';

            -- 7. Ghi AuditRecord
            INSERT INTO AuditRecord
                (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            SELECT @SystemUserID,
                   'SYSTEM_WAITLIST_OPPORTUNITY_EXPIRED',
                   'WaitlistEntry',
                   CAST(ew.WaitlistEntryID AS VARCHAR(64)),
                   'UPDATE',
                   @Now,
                   '{"EntryStatus":"Expired"}'
            FROM   #ExpiredWaitlist ew
            JOIN   WaitlistEntry we ON ew.WaitlistEntryID = we.WaitlistEntryID
            WHERE  we.EntryStatus = 'Expired';
        END

        DROP TABLE #ExpiredBookings;
        DROP TABLE #ExpiredWaitlist;
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#ExpiredBookings') IS NOT NULL DROP TABLE #ExpiredBookings;
        IF OBJECT_ID('tempdb..#ExpiredWaitlist') IS NOT NULL DROP TABLE #ExpiredWaitlist;
        THROW;
    END CATCH
END;
GO
