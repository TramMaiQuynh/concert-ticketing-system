-- ============================================================
-- sp_ProcessQueueAdmission (BP11 / SIP3 / FR66-FR67 / BR39, BR45-BR47)
-- Tien trinh tu dong: 
--  1. Quet cac QueueEntry 'Admitted' da het han -> 'Expired'.
--  2. Admit bo sung tu 'Waiting' len 'Admitted' theo dung 
--     FairAccessPolicy va AdmissionCapacity.
-- Duoc goi dinh ky boi SQL Agent Job (SIP3).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ProcessQueueAdmission
(
    @ConcertID INT,
    @AdmitCount INT = NULL -- Neu NULL, se tu dong admit cho day Capacity.
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID INT;
    SELECT @SystemUserID = UserID FROM UserAccount WHERE Username = 'system';

    DECLARE @Now DATETIME2(7) = SYSDATETIME();
    DECLARE @AdmissionValidity INT;
    SELECT @AdmissionValidity = CAST(ConfigurationValue AS INT)
    FROM   SystemConfiguration
    WHERE  ConfigurationKey = 'Queue_Admission_Validity';
    SET @AdmissionValidity = ISNULL(@AdmissionValidity, 600);

    -- Pre-flight: Concert OnSale + Queue Open
    IF NOT EXISTS (
        SELECT 1 FROM Concert
        WHERE  ConcertID = @ConcertID AND ConcertStatus = 'OnSale' AND SalesPaused = 0
    ) RETURN;

    DECLARE @QueueID INT, @Capacity INT, @Policy VARCHAR(32);
    SELECT @QueueID = QueueID, @Capacity = AdmissionCapacity, @Policy = ISNULL(FairAccessPolicy, 'FIFO')
    FROM   Queue
    WHERE  ConcertID = @ConcertID AND QueueStatus = 'Open';

    IF @QueueID IS NULL RETURN;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- CRIT-14: Dung AppLock theo ConcertID de ngan chan race condition khi Job va Admin cung chay
        DECLARE @LockResource NVARCHAR(128) = 'ProcessQueueAdmission_' + CAST(@ConcertID AS NVARCHAR(20));
        DECLARE @LockResult INT;
        EXEC @LockResult = sp_getapplock
            @Resource = @LockResource,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 0;

        IF @LockResult < 0
        BEGIN
            -- Luong khac dang xu ly, bo qua (khong can error vi day thuong la background job)
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- 1. XU LY EXPIRED
        -- Nhieu user duoc Admitted nhung khong mua ve se bi Expired slot.
        CREATE TABLE #ExpiredEntries (QueueEntryID INT NOT NULL PRIMARY KEY);
        INSERT INTO #ExpiredEntries (QueueEntryID)
        SELECT QueueEntryID
        FROM   QueueEntry WITH (UPDLOCK)
        WHERE  QueueID = @QueueID
          AND  QueueStatus = 'Admitted'
          AND  AdmissionExpiryTimestamp < @Now;

        IF EXISTS (SELECT 1 FROM #ExpiredEntries)
        BEGIN
            UPDATE qe
            SET    qe.QueueStatus = 'Expired',
                   qe.ExitTimestamp = @Now
            FROM   QueueEntry qe
            JOIN   #ExpiredEntries e ON e.QueueEntryID = qe.QueueEntryID;

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            SELECT @SystemUserID, 'SYSTEM_QUEUE_ADMISSION_EXPIRED', 'QueueEntry', CAST(QueueEntryID AS VARCHAR(64)), 'UPDATE', @Now,
                   '{"QueueStatus":"Expired"}'
            FROM   #ExpiredEntries;
        END

        -- 2. Tinh toan Slot trong
        DECLARE @AdmittedNow INT;
        SELECT @AdmittedNow = COUNT(*)
        FROM   QueueEntry WITH (UPDLOCK)
        WHERE  QueueID = @QueueID
          AND  QueueStatus = 'Admitted';

        DECLARE @Slots INT = @Capacity - @AdmittedNow;

        -- Neu chi dinh @AdmitCount thi lay min(@AdmitCount, @Slots)
        DECLARE @ToAdmit INT = 0;
        IF @Slots > 0 
        BEGIN
            IF @AdmitCount IS NOT NULL 
                SET @ToAdmit = CASE WHEN @AdmitCount < @Slots THEN @AdmitCount ELSE @Slots END;
            ELSE 
                SET @ToAdmit = @Slots;
        END

        IF @ToAdmit > 0
        BEGIN
            -- 3. ADMIT THEM
            CREATE TABLE #ToAdmit (QueueEntryID INT NOT NULL PRIMARY KEY);

            IF @Policy = 'RANDOM'
            BEGIN
                INSERT INTO #ToAdmit (QueueEntryID)
                SELECT TOP (@ToAdmit) QueueEntryID
                FROM   QueueEntry WITH (UPDLOCK)
                WHERE  QueueID = @QueueID AND QueueStatus = 'Waiting'
                ORDER  BY NEWID();
            END
            ELSE -- FIFO
            BEGIN
                -- I-18: Xu ly NULL sorting de NULL khong bi xep len dau
                INSERT INTO #ToAdmit (QueueEntryID)
                SELECT TOP (@ToAdmit) QueueEntryID
                FROM   QueueEntry WITH (UPDLOCK)
                WHERE  QueueID = @QueueID AND QueueStatus = 'Waiting'
                ORDER  BY CASE WHEN AdmissionPosition IS NULL THEN 1 ELSE 0 END ASC, AdmissionPosition ASC, JoinedTimestamp ASC;
            END

            IF EXISTS (SELECT 1 FROM #ToAdmit)
            BEGIN
                UPDATE qe
                SET    qe.QueueStatus              = 'Admitted',
                       qe.AdmissionTimestamp       = @Now,
                       qe.AdmissionExpiryTimestamp = DATEADD(SECOND, @AdmissionValidity, @Now)
                FROM   QueueEntry qe
                JOIN   #ToAdmit t ON t.QueueEntryID = qe.QueueEntryID;

                INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
                SELECT @SystemUserID, 'SYSTEM_QUEUE_ADMITTED', 'QueueEntry', CAST(t.QueueEntryID AS VARCHAR(64)), 'UPDATE', @Now,
                       '{"QueueStatus":"Admitted","AdmissionExpiryTimestamp":"' + CONVERT(VARCHAR(33), DATEADD(SECOND, @AdmissionValidity, @Now), 126) + '"}'
                FROM   #ToAdmit t;
            END

            DROP TABLE #ToAdmit;
        END

        DROP TABLE #ExpiredEntries;
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#ExpiredEntries') IS NOT NULL DROP TABLE #ExpiredEntries;
        IF OBJECT_ID('tempdb..#ToAdmit') IS NOT NULL DROP TABLE #ToAdmit;
        THROW;
    END CATCH
END;
GO
