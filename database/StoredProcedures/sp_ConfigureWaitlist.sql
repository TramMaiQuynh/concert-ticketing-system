-- ============================================================
-- sp_ConfigureWaitlist (BP10 / FR60-FR63 / BR43)
-- Cau hinh Waitlist cua mot Concert: AllocationPolicy (FIFO/RANDOM) va
-- trang thai Open/Closed. Tao Waitlist neu chua co, cap nhat neu da co.
-- Quyen: Organizer so huu Concert hoac Admin.
--
-- Ly do SP nay ton tai (§24.4): giong sp_ConfigureQueue - truoc day Waitlist chi
-- duoc tao ngam boi nguoi dang ky dau tien voi AllocationPolicy hardcode 'FIFO',
-- nen 'RANDOM' trong CHK_Waitlist_Policy la gia tri khong the dat toi va nhanh
-- `IF @FairAccessPolicy = 'RANDOM'` trong sp_AllocateWaitlist la code chet.
-- BR43 quy dinh RANDOM ton tai chinh de chong bot/spam dang ky som, tuc la mot
-- nang luc chong gian lan that su dang bi vo hieu hoa.
--
-- Tham so NULL = giu nguyen gia tri hien tai.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureWaitlist
(
    @ActorUserID      INT,
    @ConcertID        INT,
    @AllocationPolicy VARCHAR(32) = NULL,
    @WaitlistStatus   VARCHAR(32) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT, @WaitlistEnabled BIT, @ConcertExists BIT = 0;
        SELECT @OrganizerUserID = OrganizerUserID,
               @WaitlistEnabled = WaitlistEnabled,
               @ConcertExists   = 1
        FROM   Concert WHERE ConcertID = @ConcertID;

        IF @ConcertExists = 0
            THROW 59511, 'sp_ConfigureWaitlist: Concert khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin'
                         AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 59512, 'sp_ConfigureWaitlist: Actor khong co quyen.', 1;

        IF @AllocationPolicy IS NOT NULL AND @AllocationPolicy NOT IN ('FIFO', 'RANDOM')
            THROW 59513, 'sp_ConfigureWaitlist: AllocationPolicy phai la FIFO hoac RANDOM (BR43).', 1;

        IF @WaitlistStatus IS NOT NULL AND @WaitlistStatus NOT IN ('Open', 'Closed')
            THROW 59514, 'sp_ConfigureWaitlist: WaitlistStatus phai la Open hoac Closed.', 1;

        -- Doi xung voi §12.15.1 cua Queue: co Concert.WaitlistEnabled la cau hinh
        -- bat/tat kha nang; khong duoc mo Waitlist khi kha nang do dang tat.
        IF @WaitlistStatus = 'Open' AND @WaitlistEnabled = 0
            THROW 59515, 'sp_ConfigureWaitlist: Khong the mo Waitlist khi Concert chua bat WaitlistEnabled.', 1;

        DECLARE @WaitlistID INT;
        SELECT @WaitlistID = WaitlistID FROM Waitlist WITH (UPDLOCK) WHERE ConcertID = @ConcertID;

        IF @WaitlistID IS NULL
        BEGIN
            IF @WaitlistEnabled = 0
                THROW 59515, 'sp_ConfigureWaitlist: Khong the mo Waitlist khi Concert chua bat WaitlistEnabled.', 1;

            INSERT INTO Waitlist (ConcertID, WaitlistStatus, OpenTimestamp, AllocationPolicy)
            VALUES (@ConcertID,
                    ISNULL(@WaitlistStatus, 'Open'),
                    SYSDATETIME(),
                    ISNULL(@AllocationPolicy, 'FIFO'));   -- BR43: FIFO la mac dinh he thong

            SET @WaitlistID = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE Waitlist
            SET    AllocationPolicy = COALESCE(@AllocationPolicy, AllocationPolicy),
                   WaitlistStatus   = COALESCE(@WaitlistStatus, WaitlistStatus),
                   CloseTimestamp   = CASE WHEN @WaitlistStatus = 'Closed' THEN SYSDATETIME() ELSE CloseTimestamp END
            WHERE  WaitlistID = @WaitlistID;
        END

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        SELECT @ActorUserID, 'WAITLIST_CONFIGURED', 'Waitlist', CAST(w.WaitlistID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
               '{"WaitlistStatus":"' + w.WaitlistStatus + '","AllocationPolicy":"' + w.AllocationPolicy + '"}'
        FROM   Waitlist w WHERE w.WaitlistID = @WaitlistID;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
