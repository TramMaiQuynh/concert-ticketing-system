-- ============================================================
-- sp_AssignRole (BP12 / FR47 / BR52)
-- Gan hoac thu hoi Role cho User. Chi Admin.
-- Thu hoi = set AssignmentStatus = 'Revoked' tren hang dang Active.
-- Gan = INSERT hang moi 'Active' (hoac chuyen lai Active neu da bi Revoked).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AssignRole
(
    @ActorUserID INT,
    @TargetUserID INT,
    @RoleName    NVARCHAR(255),
    @GrantOrRevoke VARCHAR(10)   -- 'Grant' | 'Revoke'
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Chi Admin duoc assign/revoke role
        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
            THROW 58401, 'sp_AssignRole: Chi Admin duoc gan/thu hoi Role.', 1;

        IF NOT EXISTS (SELECT 1 FROM UserAccount WHERE UserID = @TargetUserID)
            THROW 58402, 'sp_AssignRole: User khong ton tai.', 1;

        DECLARE @RoleID INT = (SELECT RoleID FROM Role WHERE RoleName = @RoleName AND RoleStatus = 'Active');
        IF @RoleID IS NULL
            THROW 58403, 'sp_AssignRole: Role khong ton tai hoac khong Active.', 1;

        -- Ngăn gán role cho tai khoan he thong (username = 'system')
        IF EXISTS (SELECT 1 FROM UserAccount WHERE UserID = @TargetUserID AND Username = 'system')
            THROW 58404, 'sp_AssignRole: Khong duoc gan Role cho tai khoan he thong.', 1;

        IF UPPER(@GrantOrRevoke) = 'GRANT'
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment WHERE UserID = @TargetUserID AND RoleID = @RoleID)
            BEGIN
                INSERT INTO UserRoleAssignment (UserID, RoleID, AssignedTimestamp, AssignmentStatus)
                VALUES (@TargetUserID, @RoleID, SYSDATETIME(), 'Active');
            END
            ELSE
            BEGIN
                UPDATE UserRoleAssignment
                SET AssignmentStatus = 'Active', AssignedTimestamp = SYSDATETIME()
                WHERE UserID = @TargetUserID AND RoleID = @RoleID;
            END

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'ROLE_GRANTED', 'UserRoleAssignment',
                    CAST(@TargetUserID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"Role":"' + @RoleName + '","Status":"Granted"}');
        END
        ELSE IF UPPER(@GrantOrRevoke) = 'REVOKE'
        BEGIN
            UPDATE UserRoleAssignment
            SET AssignmentStatus = 'Revoked'
            WHERE UserID = @TargetUserID AND RoleID = @RoleID AND AssignmentStatus = 'Active';

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'ROLE_REVOKED', 'UserRoleAssignment',
                    CAST(@TargetUserID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"Role":"' + @RoleName + '","Status":"Revoked"}');
        END
        ELSE
            THROW 58405, 'sp_AssignRole: GrantOrRevoke phai la Grant hoac Revoke.', 1;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO