-- ============================================================
-- sp_AllocateWaitlist (BP10 / SIP2 / BR42-BR44)
-- Phan bo co hoi Booking cho Customer trong Waitlist theo
-- FIFO (JoinedTimestamp tang dan - BR43).
-- Xu ly cho mot Concert cu the khi EventSeat duoc giai phong.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AllocateWaitlist
(
    @ConcertID   INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID INT;
    SELECT  @SystemUserID = UserID FROM UserAccount WHERE Username = 'system';

    DECLARE @Now DATETIME2(7) = SYSDATETIME();

    -- Lay thoi gian co hoi tu SystemConfiguration
    DECLARE @OpportunityDuration INT;
    SELECT  @OpportunityDuration = CAST(ConfigurationValue AS INT)
    FROM    SystemConfiguration
    WHERE   ConfigurationKey = 'Waitlist_Opportunity_Duration';
    SET @OpportunityDuration = ISNULL(@OpportunityDuration, 3600);

    -- Lay WaitlistID cua Concert
    DECLARE @WaitlistID INT;
    SELECT  @WaitlistID = WaitlistID
    FROM    Waitlist
    WHERE   ConcertID     = @ConcertID
      AND   WaitlistStatus = 'Open';

    IF @WaitlistID IS NULL RETURN;

    -- Lay danh sach EventSeat cua Concert dang Available
    -- de co the giu cho Waitlist
    DECLARE @AvailableSeatID INT;
    SELECT TOP 1 @AvailableSeatID = EventSeatID
    FROM   EventSeat
    WHERE  ConcertID       = @ConcertID
      AND  InventoryStatus = 'Available';

    IF @AvailableSeatID IS NULL RETURN;

    -- Lay Customer dau tien trong Waitlist theo FIFO (BR43)
    DECLARE @WaitlistEntryID  INT;
    DECLARE @CustomerUserID   INT;

    SELECT TOP 1
           @WaitlistEntryID = WaitlistEntryID,
           @CustomerUserID  = CustomerUserID
    FROM   WaitlistEntry
    WHERE  WaitlistID   = @WaitlistID
      AND  EntryStatus  = 'Active'
    ORDER BY JoinedTimestamp ASC;

    IF @WaitlistEntryID IS NULL RETURN;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Chuyen EventSeat -> OnHoldForWaitlist
        UPDATE EventSeat
        SET    InventoryStatus = 'OnHoldForWaitlist'
        WHERE  EventSeatID     = @AvailableSeatID
          AND  InventoryStatus = 'Available';  -- conditional

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RETURN;  -- Da bi giu boi session khac, bo qua
        END

        -- Cap co hoi cho Customer trong Waitlist (BR44)
        DECLARE @OpportunityExpiry DATETIME2(7) = DATEADD(SECOND, @OpportunityDuration, @Now);

        UPDATE WaitlistEntry
        SET    EntryStatus                = 'Granted',
               OpportunityGrantedTimestamp = @Now,
               OpportunityExpiryTimestamp  = @OpportunityExpiry
        WHERE  WaitlistEntryID = @WaitlistEntryID;

        -- Ghi AuditRecord
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@SystemUserID,
             'SYSTEM_WAITLIST_OPPORTUNITY_GRANTED',
             'WaitlistEntry',
             CAST(@WaitlistEntryID AS VARCHAR(64)),
             'UPDATE',
             @Now,
             '{"EntryStatus":"Granted","EventSeatID":' + CAST(@AvailableSeatID AS VARCHAR) + '}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
