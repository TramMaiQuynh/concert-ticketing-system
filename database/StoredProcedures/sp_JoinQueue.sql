-- ============================================================
-- sp_JoinQueue (BP11 / FR64 / BR45-BR46)
-- Customer tham gia Virtual Queue cua Concert khi Fair Access bat.
-- Neu Queue chua ton tai -> tao moi (Open) voi AdmissionCapacity va
-- FairAccessPolicy lay tu cau hinh Concert/SystemConfiguration
-- (khong hardcode - §12.15.1, §12.18).
-- Ghi AdmissionPosition (FR65) theo thu tu JoinedTimestamp (FIFO).
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
            -- Cau hinh mac dinh toan cuc (khong hardcode): §12.18
            DECLARE @DefaultCapacity INT;
            SELECT @DefaultCapacity = CAST(ConfigurationValue AS INT)
            FROM   SystemConfiguration
            WHERE  ConfigurationKey = 'Queue_Default_Admission_Capacity';
            SET @DefaultCapacity = ISNULL(@DefaultCapacity, 1000);

            INSERT INTO Queue (ConcertID, QueueStatus, AdmissionCapacity, FairAccessPolicy)
            VALUES (@ConcertID, 'Open', @DefaultCapacity, 'FIFO');
            SET @QueueID = SCOPE_IDENTITY();
            SET @Capacity = @DefaultCapacity;
        END

        -- Khong cho trung lap entry dang Waiting/Admitted cho cung Customer/Concert
        IF EXISTS (SELECT 1 FROM QueueEntry
                   WHERE QueueID = @QueueID AND CustomerUserID = @CustomerUserID
                     AND QueueStatus IN ('Waiting', 'Admitted'))
            THROW 58703, 'sp_JoinQueue: Customer da co entry trong Queue nay.', 1;

        -- FR65: ghi AdmissionPosition theo thu tu JoinedTimestamp (FIFO)
        DECLARE @Pos INT = ISNULL((SELECT MAX(AdmissionPosition) FROM QueueEntry WHERE QueueID = @QueueID), 0) + 1;

        INSERT INTO QueueEntry (QueueID, CustomerUserID, JoinedTimestamp, AdmissionPosition, QueueStatus)
        VALUES (@QueueID, @CustomerUserID, SYSDATETIME(), @Pos, 'Waiting');

        SET @NewQueueEntryID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@CustomerUserID, 'QUEUE_JOINED', 'QueueEntry',
                CAST(@NewQueueEntryID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"QueueStatus":"Waiting","AdmissionPosition":' + CAST(@Pos AS VARCHAR) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO