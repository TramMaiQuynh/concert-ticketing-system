-- ============================================================
-- sp_JoinQueue (BP11 / FR64 / BR45-BR46)
-- Customer tham gia Virtual Queue cua Concert khi Fair Access bat.
-- Neu Queue chua ton tai -> tao moi (Open) voi AdmissionCapacity lay tu
-- SystemConfiguration va FairAccessPolicy = FIFO (mac dinh he thong theo BR45b).
-- Muon doi capacity / policy / booking_ttl cho rieng Concert: dung sp_ConfigureQueue.
-- Ghi AdmissionPosition (FR65) theo thu tu tham gia.
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

        DECLARE @FairAccessEnabled BIT, @ConcertStatus VARCHAR(32);
        SELECT @FairAccessEnabled = FairAccessEnabled, @ConcertStatus = ConcertStatus
        FROM   Concert WHERE ConcertID = @ConcertID;

        IF @ConcertStatus IS NULL
            THROW 58701, 'sp_JoinQueue: Concert khong ton tai.', 1;

        IF @FairAccessEnabled = 0
            THROW 58702, 'sp_JoinQueue: Concert khong bat Fair Access.', 1;

        -- Precondition BP11: Virtual Queue phuc vu giai doan mo ban.
        -- Cho phep xep hang truoc khi mo ban (Published) vi do la muc dich cua Fair Access,
        -- nhung chan cac trang thai da ket thuc - luc do khong con gi de admission.
        IF @ConcertStatus NOT IN ('Published', 'OnSale')
            THROW 58704, 'sp_JoinQueue (BP11): Chi tham gia Queue khi Concert dang Published hoac OnSale.', 1;

        DECLARE @QueueID INT;
        SELECT @QueueID = QueueID
        FROM   Queue WHERE ConcertID = @ConcertID AND QueueStatus = 'Open';

        IF @QueueID IS NULL
        BEGIN
            -- Tao Queue theo mac dinh he thong. UQ_Queue_Concert la trong tai cuoi cung:
            -- hai nguoi cung bam "vao hang" dau tien se cung thay chua co Queue va cung
            -- INSERT; nguoi thua se nhan 2601/2627 va chi can doc lai dong vua duoc tao,
            -- thay vi lam hong ca request.
            DECLARE @DefaultCapacity INT;
            SELECT @DefaultCapacity = CAST(ConfigurationValue AS INT)
            FROM   SystemConfiguration
            WHERE  ConfigurationKey = 'Queue_Default_Admission_Capacity';

            IF @DefaultCapacity IS NULL
                THROW 58705, 'sp_JoinQueue: Thieu SystemConfiguration.Queue_Default_Admission_Capacity - kiem tra du lieu nen (§23.7).', 1;

            BEGIN TRY
                INSERT INTO Queue (ConcertID, QueueStatus, AdmissionCapacity, FairAccessPolicy)
                VALUES (@ConcertID, 'Open', @DefaultCapacity, 'FIFO');   -- BR45b: FIFO la mac dinh he thong
                SET @QueueID = SCOPE_IDENTITY();
            END TRY
            BEGIN CATCH
                IF ERROR_NUMBER() NOT IN (2601, 2627) THROW;
                SELECT @QueueID = QueueID FROM Queue WHERE ConcertID = @ConcertID AND QueueStatus = 'Open';
                IF @QueueID IS NULL
                    THROW 58706, 'sp_JoinQueue: Queue cua Concert nay dang Closed.', 1;
            END CATCH
        END

        -- Khong cho trung lap entry dang Waiting/Admitted cho cung Customer/Concert.
        -- Day la kiem tra "than thien" de tra ve loi ro nghia; bao ve THAT SU la
        -- UIX_QueueEntry_ActivePerCustomer (BR46) vi rieng IF EXISTS khong chan duoc
        -- hai request dong thoi.
        IF EXISTS (SELECT 1 FROM QueueEntry
                   WHERE QueueID = @QueueID AND CustomerUserID = @CustomerUserID
                     AND QueueStatus IN ('Waiting', 'Admitted'))
            THROW 58703, 'sp_JoinQueue: Customer da co entry trong Queue nay.', 1;

        -- FR65: AdmissionPosition tang dan theo thu tu tham gia.
        -- UPDLOCK+HOLDLOCK giu range lock tren cac dong cua Queue nay den het
        -- transaction, nen hai nguoi vao cung luc khong the nhan cung mot vi tri.
        DECLARE @Pos INT = ISNULL((SELECT MAX(AdmissionPosition)
                                   FROM QueueEntry WITH (UPDLOCK, HOLDLOCK)
                                   WHERE QueueID = @QueueID), 0) + 1;

        BEGIN TRY
            INSERT INTO QueueEntry (QueueID, CustomerUserID, JoinedTimestamp, AdmissionPosition, QueueStatus)
            VALUES (@QueueID, @CustomerUserID, SYSDATETIME(), @Pos, 'Waiting');
        END TRY
        BEGIN CATCH
            -- Thua cuoc voi mot request song song cua chinh khach hang nay.
            IF ERROR_NUMBER() IN (2601, 2627)
                THROW 58703, 'sp_JoinQueue: Customer da co entry trong Queue nay.', 1;
            THROW;
        END CATCH

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
