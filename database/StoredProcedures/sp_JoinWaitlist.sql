-- ============================================================
-- sp_JoinWaitlist (BP10 / FR60 / BR40-BR41)
-- Customer dang ky tham gia Waitlist cua Concert.
-- Dieu kien: Waitlist mo (WaitlistStatus='Open' va Concert.WaitlistEnabled=1),
--           Customer chua co entry Active cho Concert nay.
-- QueuePosition = (max position + 1).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_JoinWaitlist
(
    @CustomerUserID INT,
    @ConcertID      INT,
    @NewWaitlistEntryID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Concert + Waitlist
        DECLARE @WaitlistID INT, @IsWaitlistEnabled BIT;
        SELECT @IsWaitlistEnabled = WaitlistEnabled FROM Concert WHERE ConcertID = @ConcertID;

        IF @IsWaitlistEnabled IS NULL
            THROW 58501, 'sp_JoinWaitlist: Concert khong ton tai.', 1;

        IF @IsWaitlistEnabled = 0
            THROW 58502, 'sp_JoinWaitlist: Concert khong bat Waitlist.', 1;

        SELECT @WaitlistID = WaitlistID FROM Waitlist
        WHERE ConcertID = @ConcertID AND WaitlistStatus = 'Open';

        -- Nếu Waitlist chưa tồn tại thì tạo (mặc định Concert bật Waitlist)
        IF @WaitlistID IS NULL
        BEGIN
            INSERT INTO Waitlist (ConcertID, WaitlistStatus, OpenTimestamp, AllocationPolicy)
            VALUES (@ConcertID, 'Open', SYSDATETIME(), 'FIFO');
            SET @WaitlistID = SCOPE_IDENTITY();
        END

        -- 2. BR41: 1 Customer chi 1 entry Active/Concert
        IF EXISTS (SELECT 1 FROM WaitlistEntry
                   WHERE WaitlistID = @WaitlistID AND CustomerUserID = @CustomerUserID AND EntryStatus = 'Active')
            THROW 58503, 'sp_JoinWaitlist: Customer da co entry Active cho Concert nay.', 1;

        -- 3. Insert voi QueuePosition = max + 1
        DECLARE @Pos INT = ISNULL((SELECT MAX(QueuePosition) FROM WaitlistEntry WHERE WaitlistID = @WaitlistID), 0) + 1;

        INSERT INTO WaitlistEntry (WaitlistID, CustomerUserID, JoinedTimestamp, QueuePosition, EntryStatus)
        VALUES (@WaitlistID, @CustomerUserID, SYSDATETIME(), @Pos, 'Active');

        SET @NewWaitlistEntryID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@CustomerUserID, 'WAITLIST_JOINED', 'WaitlistEntry',
                CAST(@NewWaitlistEntryID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"QueuePosition":' + CAST(@Pos AS VARCHAR) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO