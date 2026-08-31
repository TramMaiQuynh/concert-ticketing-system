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
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
            THROW 58901, 'sp_AdminUpdateUserStatus: Chi Admin thuc hien duoc.', 1;

        IF @NewStatus NOT IN ('Active', 'Locked', 'Disabled')
            THROW 58902, 'sp_AdminUpdateUserStatus: UserStatus khong hop le.', 1;

        DECLARE @OldStatus VARCHAR(32);
        SELECT @OldStatus = AccountStatus FROM UserAccount WHERE UserID = @TargetUserID;

        IF @OldStatus IS NULL
            THROW 58903, 'sp_AdminUpdateUserStatus: User khong ton tai.', 1;

        IF EXISTS (SELECT 1 FROM UserAccount WHERE UserID = @TargetUserID AND Username = 'system')
            THROW 58904, 'sp_AdminUpdateUserStatus: Khong doi trang thai tai khoan he thong.', 1;

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