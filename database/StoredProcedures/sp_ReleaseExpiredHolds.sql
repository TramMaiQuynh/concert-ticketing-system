-- ============================================================
-- sp_ReleaseExpiredHolds (BP7 / SIP1 / BR18-BR19, BR33a)
-- Tien trinh tu dong: tim va giai phong tat ca Booking Pending
-- da qua han HoldExpiryDatetime ma chua thanh toan, cung nhu
-- WaitlistEntry Opportunity het han ma chua dung (SIP2).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ReleaseExpiredHolds
(
    @ConcertID INT = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID INT;
    SELECT  @SystemUserID = UserID FROM UserAccount WHERE Username = 'system';

    DECLARE @Now DATETIME2(7) = SYSDATETIME();

    -- 1. Tim cac Booking can xu ly
    CREATE TABLE #ExpiredBookings (BookingID INT NOT NULL, ConcertID INT NOT NULL);
    INSERT INTO #ExpiredBookings (BookingID, ConcertID)
    SELECT BookingID, ConcertID
    FROM   Booking WITH (UPDLOCK) -- khoa truoc de ngan chan race condition thay doi trang thai
    WHERE  BookingStatus      = 'Pending'
      AND  HoldExpiryDatetime < @Now
      AND  (@ConcertID IS NULL OR ConcertID = @ConcertID);

    -- 2. Tim cac WaitlistEntry can xu ly (danh sach co hoi da cap phat nhung het han)
    CREATE TABLE #ExpiredWaitlist (WaitlistEntryID INT NOT NULL, ConcertID INT NOT NULL);
    INSERT INTO #ExpiredWaitlist (WaitlistEntryID, ConcertID)
    SELECT we.WaitlistEntryID, w.ConcertID
    FROM   WaitlistEntry we WITH (UPDLOCK)
    JOIN   Waitlist w ON w.WaitlistID = we.WaitlistID
    WHERE  we.EntryStatus = 'Granted'
      AND  we.OpportunityExpiryTimestamp < @Now
      AND  (@ConcertID IS NULL OR w.ConcertID = @ConcertID);

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
            -- 1. Chuyen Booking -> Expired (CRIT-11: Guard condition)
            UPDATE Booking
            SET    BookingStatus     = 'Expired',
                   ExpiredTimestamp  = @Now
            WHERE  BookingID IN (SELECT BookingID FROM #ExpiredBookings)
              AND  BookingStatus     = 'Pending';

            -- Xoa cac booking khong con Pending khoi bang tam de khong giai phong nham
            DELETE FROM #ExpiredBookings WHERE BookingID NOT IN (SELECT BookingID FROM Booking WHERE BookingStatus = 'Expired' AND ExpiredTimestamp = @Now);

            -- 2. Chuyen Allocation -> Released
            UPDATE BookingEventSeatAllocation
            SET    AllocationStatus  = 'Released',
                   ReleaseTimestamp  = @Now
            WHERE  BookingID         IN (SELECT BookingID FROM #ExpiredBookings)
              AND  AllocationStatus  = 'Active';

            -- 3. Tra lai EventSeat.
            -- BR33a / CRIT-11: Chi chuyen thanh OnHoldForWaitlist neu co Active WaitlistEntry CHO DUNG CATEGORY NAY
            UPDATE es
            SET    InventoryStatus = CASE 
                                     WHEN EXISTS (
                                         SELECT 1 FROM Waitlist w 
                                         JOIN WaitlistEntry we ON w.WaitlistID = we.WaitlistID 
                                         WHERE w.ConcertID = es.ConcertID 
                                           AND w.WaitlistStatus = 'Open' 
                                           AND we.TicketCategoryID = es.TicketCategoryID 
                                           AND we.EntryStatus = 'Active'
                                     )
                                     THEN 'OnHoldForWaitlist' 
                                     ELSE 'Available' 
                                     END
            FROM   EventSeat es
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
            -- 5. Tim va giai phong co hoi Waitlist het han (Guard condition)
            UPDATE WaitlistEntry
            SET    EntryStatus = 'Expired'
            WHERE  WaitlistEntryID IN (SELECT WaitlistEntryID FROM #ExpiredWaitlist)
              AND  EntryStatus = 'Granted';

            DELETE FROM #ExpiredWaitlist WHERE WaitlistEntryID NOT IN (SELECT WaitlistEntryID FROM WaitlistEntry WHERE EntryStatus = 'Expired');

            -- 6. Giai phong WaitlistEntryEventSeatAllocation
            UPDATE WaitlistEntryEventSeatAllocation
            SET    AllocationStatus = 'Released',
                   ReleaseTimestamp = @Now
            WHERE  WaitlistEntryID IN (SELECT WaitlistEntryID FROM #ExpiredWaitlist)
              AND  AllocationStatus = 'Active';

            -- 7. Tra lai EventSeat 
            -- BR33a / CRIT-11: Kiem tra Waitlist va Category hien tai.
            UPDATE es
            SET    InventoryStatus = CASE 
                                     WHEN EXISTS (
                                         SELECT 1 FROM Waitlist w 
                                         JOIN WaitlistEntry we ON w.WaitlistID = we.WaitlistID 
                                         WHERE w.ConcertID = es.ConcertID 
                                           AND w.WaitlistStatus = 'Open' 
                                           AND we.TicketCategoryID = es.TicketCategoryID 
                                           AND we.EntryStatus = 'Active'
                                     )
                                     THEN 'OnHoldForWaitlist' 
                                     ELSE 'Available' 
                                     END
            FROM   EventSeat es
            WHERE  EventSeatID IN (
                       SELECT wea.EventSeatID
                       FROM WaitlistEntryEventSeatAllocation wea
                       JOIN #ExpiredWaitlist ew ON ew.WaitlistEntryID = wea.WaitlistEntryID
                   )
              AND  InventoryStatus = 'OnHoldForWaitlist';

            -- 8. Ghi AuditRecord
            INSERT INTO AuditRecord
                (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            SELECT @SystemUserID,
                   'SYSTEM_WAITLIST_OPPORTUNITY_EXPIRED',
                   'WaitlistEntry',
                   CAST(WaitlistEntryID AS VARCHAR(64)),
                   'UPDATE',
                   @Now,
                   '{"EntryStatus":"Expired"}'
            FROM   #ExpiredWaitlist;
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
