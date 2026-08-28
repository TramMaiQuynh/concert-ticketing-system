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

    -- 1. Kiem tra Concert phai OnSale va khong SalesPaused
    IF NOT EXISTS (
        SELECT 1 FROM Concert
        WHERE  ConcertID    = @ConcertID
          AND  ConcertStatus = 'OnSale'
          AND  SalesPaused   = 0
    ) RETURN;

    -- 2. Lay WaitlistID cua Concert
    DECLARE @WaitlistID INT;
    SELECT  @WaitlistID = WaitlistID
    FROM    Waitlist
    WHERE   ConcertID     = @ConcertID
      AND   WaitlistStatus = 'Open';

    IF @WaitlistID IS NULL RETURN;

    -- 3. Lay danh sach EventSeat cua Concert dang Available
    DECLARE @AvailableSeatID INT;
    SELECT TOP 1 @AvailableSeatID = EventSeatID
    FROM   EventSeat
    WHERE  ConcertID       = @ConcertID
      AND  InventoryStatus = 'Available';

    IF @AvailableSeatID IS NULL RETURN;

    -- 4. Kiem tra Purchase Limit cua Concert
    DECLARE @PurchaseLimit INT;
    SELECT  @PurchaseLimit = PurchaseLimit
    FROM    Concert
    WHERE   ConcertID = @ConcertID;

    -- 5. Lay Customer dau tien trong Waitlist theo FIFO (BR43)
    --    va phai con TRONG GIOI HAN MUA VE (Purchase Limit)
    DECLARE @WaitlistEntryID  INT;
    DECLARE @CustomerUserID   INT;

    SELECT TOP 1
           @WaitlistEntryID = WaitlistEntryID,
           @CustomerUserID  = CustomerUserID
    FROM   WaitlistEntry we
    WHERE  we.WaitlistID   = @WaitlistID
      AND  we.EntryStatus  = 'Active'
      AND  (dbo.fn_GetCustomerTicketCount(we.CustomerUserID, @ConcertID) + 1) <= @PurchaseLimit
    ORDER BY we.JoinedTimestamp ASC;

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
               OpportunityExpiryTimestamp  = @OpportunityExpiry,
               OfferedEventSeatID          = @AvailableSeatID
        WHERE  WaitlistEntryID = @WaitlistEntryID
          AND  EntryStatus = 'Active';  -- conditional

        IF @@ROWCOUNT = 0
        BEGIN
            ROLLBACK TRANSACTION;
            RETURN;  -- WaitlistEntry da bi thay doi boi session khac
        END

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
             '{"EntryStatus":"Granted","OfferedEventSeatID":' + CAST(@AvailableSeatID AS VARCHAR) + '}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
