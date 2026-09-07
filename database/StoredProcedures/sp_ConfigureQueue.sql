-- ============================================================
-- sp_ConfigureQueue (BP11 / FR64a / BR45, BR45b, BR47, BR47b)
-- Cau hinh Virtual Queue cua mot Concert: admission_capacity, queue_strategy
-- (FIFO/RANDOM) va booking_ttl. Tao Queue neu chua co, cap nhat neu da co.
-- Quyen: Organizer so huu Concert hoac Admin.
--
-- Ly do SP nay ton tai (§24.4 - moi duong du lieu phai co ben ghi):
--   FR64a yeu cau Actor co quyen cau hinh admission_capacity, queue_strategy va
--   booking_ttl CHO TUNG CONCERT. Truoc day khong SP nao ghi ba gia tri do:
--   Queue chi duoc tao ngam boi nguoi dau tien bam "vao hang", voi FairAccessPolicy
--   hardcode 'FIFO' va booking_ttl lay tu mot hang so toan cuc. Hau qua:
--     - 'RANDOM' trong CHK_Queue_Policy la gia tri KHONG THE dat toi, keo theo ca
--       nhanh `IF @Policy = 'RANDOM'` trong sp_ProcessQueueAdmission thanh code chet;
--     - moi Concert dung chung mot booking_ttl du do "nong" hoan toan khac nhau.
--
-- Quy uoc tham so:
--   NULL = giu nguyen gia tri hien tai.
--   @InheritGlobalAdmissionValidity = 1 -> dat AdmissionValiditySeconds ve NULL,
--   tuc ke thua SystemConfiguration.Queue_Admission_Validity. (Dung co rieng thay vi
--   mot gia tri quy uoc nhu 0 de khong lan lon "khong doi" voi "tra ve mac dinh".)
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureQueue
(
    @ActorUserID                    INT,
    @ConcertID                      INT,
    @AdmissionCapacity              INT         = NULL,
    @FairAccessPolicy               VARCHAR(32) = NULL,
    @AdmissionValiditySeconds       INT         = NULL,
    @InheritGlobalAdmissionValidity BIT         = 0,
    @QueueStatus                    VARCHAR(32) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT, @FairAccessEnabled BIT;
        SELECT @OrganizerUserID = OrganizerUserID, @FairAccessEnabled = FairAccessEnabled
        FROM   Concert WHERE ConcertID = @ConcertID;

        IF @OrganizerUserID IS NULL AND NOT EXISTS (SELECT 1 FROM Concert WHERE ConcertID = @ConcertID)
            THROW 59501, 'sp_ConfigureQueue: Concert khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin'
                         AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 59502, 'sp_ConfigureQueue: Actor khong co quyen.', 1;

        IF @FairAccessPolicy IS NOT NULL AND @FairAccessPolicy NOT IN ('FIFO', 'RANDOM')
            THROW 59503, 'sp_ConfigureQueue: FairAccessPolicy phai la FIFO hoac RANDOM (BR45b).', 1;

        IF @AdmissionCapacity IS NOT NULL AND @AdmissionCapacity <= 0
            THROW 59504, 'sp_ConfigureQueue: AdmissionCapacity phai lon hon 0 (BR47).', 1;

        IF @AdmissionValiditySeconds IS NOT NULL AND @AdmissionValiditySeconds <= 0
            THROW 59505, 'sp_ConfigureQueue: AdmissionValiditySeconds (booking_ttl) phai lon hon 0 (BR47b).', 1;

        IF @QueueStatus IS NOT NULL AND @QueueStatus NOT IN ('Open', 'Closed')
            THROW 59506, 'sp_ConfigureQueue: QueueStatus phai la Open hoac Closed.', 1;

        -- §12.15.1: co Concert.FairAccessEnabled la cau hinh bat/tat KHA NANG;
        -- Queue chi duoc mo khi kha nang do dang bat. Neu tat thi Queue phai Closed.
        IF @QueueStatus = 'Open' AND @FairAccessEnabled = 0
            THROW 59507, 'sp_ConfigureQueue: Khong the mo Queue khi Concert chua bat FairAccessEnabled (§12.15.1).', 1;

        DECLARE @QueueID INT;
        SELECT @QueueID = QueueID FROM Queue WITH (UPDLOCK) WHERE ConcertID = @ConcertID;

        IF @QueueID IS NULL
        BEGIN
            IF @FairAccessEnabled = 0
                THROW 59507, 'sp_ConfigureQueue: Khong the mo Queue khi Concert chua bat FairAccessEnabled (§12.15.1).', 1;

            DECLARE @DefaultCapacity INT;
            SELECT @DefaultCapacity = CAST(ConfigurationValue AS INT)
            FROM   SystemConfiguration
            WHERE  ConfigurationKey = 'Queue_Default_Admission_Capacity';

            INSERT INTO Queue (ConcertID, QueueStatus, AdmissionCapacity, FairAccessPolicy, AdmissionValiditySeconds)
            VALUES (@ConcertID,
                    ISNULL(@QueueStatus, 'Open'),
                    ISNULL(@AdmissionCapacity, @DefaultCapacity),
                    ISNULL(@FairAccessPolicy, 'FIFO'),   -- BR45b: FIFO la mac dinh he thong
                    CASE WHEN @InheritGlobalAdmissionValidity = 1 THEN NULL ELSE @AdmissionValiditySeconds END);

            SET @QueueID = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE Queue
            SET    AdmissionCapacity        = COALESCE(@AdmissionCapacity, AdmissionCapacity),
                   FairAccessPolicy         = COALESCE(@FairAccessPolicy, FairAccessPolicy),
                   AdmissionValiditySeconds = CASE
                                                  WHEN @InheritGlobalAdmissionValidity = 1 THEN NULL
                                                  ELSE COALESCE(@AdmissionValiditySeconds, AdmissionValiditySeconds)
                                              END,
                   QueueStatus              = COALESCE(@QueueStatus, QueueStatus)
            WHERE  QueueID = @QueueID;
        END

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        SELECT @ActorUserID, 'QUEUE_CONFIGURED', 'Queue', CAST(q.QueueID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
               '{"QueueStatus":"' + q.QueueStatus +
               '","AdmissionCapacity":' + CAST(q.AdmissionCapacity AS VARCHAR) +
               ',"FairAccessPolicy":"' + q.FairAccessPolicy +
               '","AdmissionValiditySeconds":' + ISNULL(CAST(q.AdmissionValiditySeconds AS VARCHAR), 'null') + '}'
        FROM   Queue q WHERE q.QueueID = @QueueID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
