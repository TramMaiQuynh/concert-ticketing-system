-- ============================================================
-- sp_JoinQueue (BP11 / FR64 / BR45-BR46)
-- Customer tham gia Virtual Queue cua Concert khi Fair Access bat.
-- Neu Queue chua ton tai -> tao moi (Open). So Customer dong thoi
-- trong Booking Flow duoc gioi han boi AdmissionCapacity (BR47).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_JoinQueue
(
    @CustomerUserID INT,
    @ConcertID      INT,
    @NewQueueEntryID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @FairAccessEnabled BIT;
        SELECT @FairAccessEnabled = FairAccessEnabled FROM Concert WHERE ConcertID = @ConcertID;

        IF @FairAccessEnabled IS NULL
            THROW 58701, 'sp_JoinQueue: Concert khong ton tai.', 1;

        IF @FairAccessEnabled = 0
            THROW 58702, 'sp_JoinQueue: Concert khong bat Fair Access.', 1;

        DECLARE @QueueID INT, @Capacity INT;
        SELECT @QueueID = QueueID, @Capacity = AdmissionCapacity
        FROM Queue WHERE ConcertID = @ConcertID AND QueueStatus = 'Open';

        IF @QueueID IS NULL
        BEGIN
            INSERT INTO Queue (ConcertID, QueueStatus, AdmissionCapacity, FairAccessPolicy)
            VALUES (@ConcertID, 'Open', 1000, 'FIFO');
            SET @QueueID = SCOPE_IDENTITY();
            SET @Capacity = 1000;
        END

        -- Khong cho trung lap entry dang Waiting/Admitted cho cung Customer/Concert
        IF EXISTS (SELECT 1 FROM QueueEntry
                   WHERE QueueID = @QueueID AND CustomerUserID = @CustomerUserID
                     AND QueueStatus IN ('Waiting', 'Admitted'))
            THROW 58703, 'sp_JoinQueue: Customer da co entry trong Queue nay.', 1;

        INSERT INTO QueueEntry (QueueID, CustomerUserID, JoinedTimestamp, QueueStatus)
        VALUES (@QueueID, @CustomerUserID, SYSDATETIME(), 'Waiting');

        SET @NewQueueEntryID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@CustomerUserID, 'QUEUE_JOINED', 'QueueEntry',
                CAST(@NewQueueEntryID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"QueueStatus":"Waiting"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO