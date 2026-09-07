-- ============================================================
-- sp_AdminUpdateUserStatus (BP12 / FR46 / BR52)
-- Admin khoa/mo khoa/vô hiệu hóa User Account.
-- Khong cho thay doi tai khoan 'system'.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AdminUpdateUserStatus
(
    @ActorUserID INT,
    @TargetUserID INT,
    @NewStatus   VARCHAR(32)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 58901, 'sp_AdminUpdateUserStatus: Chi Admin thuc hien duoc.', 1;

        IF @NewStatus NOT IN ('Active', 'Locked', 'Disabled')
            THROW 58902, 'sp_AdminUpdateUserStatus: UserStatus khong hop le.', 1;

        DECLARE @OldStatus VARCHAR(32);
        SELECT @OldStatus = AccountStatus
        FROM   UserAccount WITH (UPDLOCK)
        WHERE  UserID = @TargetUserID;

        IF @OldStatus IS NULL
            THROW 58903, 'sp_AdminUpdateUserStatus: User khong ton tai.', 1;

        IF EXISTS (SELECT 1 FROM UserAccount WHERE UserID = @TargetUserID AND Username = 'system')
            THROW 58904, 'sp_AdminUpdateUserStatus: Khong doi trang thai tai khoan he thong.', 1;

        -- UAI02 (BR52): Admin khong duoc tu khoa/vo hieu hoa chinh minh.
        -- Chi Admin moi goi duoc SP nay (da kiem tra o tren), nen @ActorUserID luon mang Role Admin.
        IF @ActorUserID = @TargetUserID AND @NewStatus <> 'Active'
            THROW 58905, 'sp_AdminUpdateUserStatus (UAI02): Admin khong duoc tu khoa hoac vo hieu hoa chinh minh.', 1;

        -- UAI01 (BR52): thao tac khong duoc lam so Admin dang Active giam ve 0.
        -- Chi can kiem tra khi Target dang la mot Admin Active va bi chuyen khoi trang thai Active.
        IF @NewStatus <> 'Active'
           AND EXISTS (SELECT 1 FROM UserRoleAssignment ura
                       JOIN   Role r ON r.RoleID = ura.RoleID
                       WHERE  ura.UserID = @TargetUserID
                         AND  r.RoleName = 'Admin'
                         AND  ura.AssignmentStatus = 'Active')
        BEGIN
            -- HOLDLOCK giu range lock den het transaction: chan truong hop hai Admin cuoi cung
            -- bi khoa dong thoi, moi phien deu thay phien kia van con Active (aggregate constraint).
            IF NOT EXISTS (
                SELECT 1
                FROM   UserAccount ua WITH (UPDLOCK, HOLDLOCK)
                JOIN   UserRoleAssignment ura ON ura.UserID = ua.UserID
                JOIN   Role r ON r.RoleID = ura.RoleID
                WHERE  r.RoleName            = 'Admin'
                  AND  ura.AssignmentStatus  = 'Active'
                  AND  ua.AccountStatus      = 'Active'
                  AND  ua.UserID            <> @TargetUserID)
                THROW 58906, 'sp_AdminUpdateUserStatus (UAI01): Khong the khoa Admin Active cuoi cung cua he thong.', 1;
        END

        UPDATE UserAccount SET AccountStatus = @NewStatus, UpdatedTimestamp = SYSDATETIME()
        WHERE UserID = @TargetUserID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'USER_STATUS_CHANGED', 'UserAccount',
                CAST(@TargetUserID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"AccountStatus":"' + @OldStatus + '"}',
                '{"AccountStatus":"' + @NewStatus + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO