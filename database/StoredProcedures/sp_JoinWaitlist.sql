-- ============================================================
-- sp_JoinWaitlist (BP10 / FR60 / BR40-BR41)
-- Customer dang ky tham gia Waitlist cua Concert.
-- Dieu kien: Waitlist mo (WaitlistStatus='Open' va Concert.WaitlistEnabled=1),
--           Customer chua co entry Active cho Concert nay.
-- QueuePosition = (max position + 1).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_JoinWaitlist
(
    @CustomerUserID     INT,
    @ConcertID          INT,
    @TicketCategoryID   INT,
    @RequestedQuantity  INT,
    @NewWaitlistEntryID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @RequestedQuantity <= 0
        THROW 58504, 'sp_JoinWaitlist: RequestedQuantity phai lon hon 0.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Concert + Waitlist
        DECLARE @WaitlistID INT, @IsWaitlistEnabled BIT, @PurchaseLimit INT;
        SELECT @IsWaitlistEnabled = WaitlistEnabled, @PurchaseLimit = PurchaseLimit FROM Concert WHERE ConcertID = @ConcertID;

        IF @IsWaitlistEnabled IS NULL
            THROW 58501, 'sp_JoinWaitlist: Concert khong ton tai.', 1;

        IF @IsWaitlistEnabled = 0
            THROW 58502, 'sp_JoinWaitlist: Concert khong bat Waitlist.', 1;

        -- Validate TicketCategoryID thuoc Concert
        IF NOT EXISTS (SELECT 1 FROM TicketCategory WHERE TicketCategoryID = @TicketCategoryID AND ConcertID = @ConcertID)
            THROW 58505, 'sp_JoinWaitlist: TicketCategory khong hop le cho Concert nay.', 1;

        IF @RequestedQuantity > @PurchaseLimit
            THROW 58506, 'sp_JoinWaitlist: RequestedQuantity vuot qua PurchaseLimit cua Concert.', 1;

        SELECT @WaitlistID = WaitlistID FROM Waitlist
        WHERE ConcertID = @ConcertID AND WaitlistStatus = 'Open';

        -- Nếu Waitlist chưa tồn tại thì tạo (mặc định Concert bật Waitlist)
        IF @WaitlistID IS NULL
        BEGIN
            INSERT INTO Waitlist (ConcertID, WaitlistStatus, OpenTimestamp, AllocationPolicy)
            VALUES (@ConcertID, 'Open', SYSDATETIME(), 'FIFO');
            SET @WaitlistID = SCOPE_IDENTITY();
        END

        -- 2. BR41: 1 Customer chi 1 entry Active cho cung Concert, bat ke TicketCategory
        IF EXISTS (SELECT 1 FROM WaitlistEntry
                   WHERE WaitlistID = @WaitlistID AND CustomerUserID = @CustomerUserID AND EntryStatus IN ('Active', 'Granted'))
            THROW 58503, 'sp_JoinWaitlist: Customer da co co hoi Waitlist dang cho hoac chua su dung cho Concert nay.', 1;

        -- 3. Insert voi QueuePosition = max + 1
        DECLARE @Pos INT = ISNULL((SELECT MAX(QueuePosition) FROM WaitlistEntry WHERE WaitlistID = @WaitlistID), 0) + 1;

        INSERT INTO WaitlistEntry (WaitlistID, CustomerUserID, TicketCategoryID, RequestedQuantity, JoinedTimestamp, QueuePosition, EntryStatus)
        VALUES (@WaitlistID, @CustomerUserID, @TicketCategoryID, @RequestedQuantity, SYSDATETIME(), @Pos, 'Active');

        SET @NewWaitlistEntryID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@CustomerUserID, 'WAITLIST_JOINED', 'WaitlistEntry',
                CAST(@NewWaitlistEntryID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"QueuePosition":' + CAST(@Pos AS VARCHAR) + ',"TicketCategoryID":' + CAST(@TicketCategoryID AS VARCHAR) + ',"RequestedQuantity":' + CAST(@RequestedQuantity AS VARCHAR) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO