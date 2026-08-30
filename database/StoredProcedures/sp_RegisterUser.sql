-- ============================================================
-- sp_RegisterUser 
-- Dang ky tai khoan khach hang moi va gan Role mac dinh (Customer).
-- ============================================================
CREATE PROCEDURE dbo.sp_RegisterUser
(
    @Username      VARCHAR(64),
    @Email         NVARCHAR(255),
    @PasswordHash  NVARCHAR(255),
    @DisplayName   NVARCHAR(255),
    @NewUserID     INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Kiem tra Username da ton tai chua
        IF EXISTS (SELECT 1 FROM UserAccount WHERE Username = @Username)
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 57001, 'sp_RegisterUser: Username da ton tai.', 1;
        END

        -- 2. Tao UserAccount
        INSERT INTO UserAccount (Username, Email, PasswordHash, DisplayName, AccountStatus)
        VALUES (@Username, @Email, @PasswordHash, @DisplayName, 'Active');

        SET @NewUserID = SCOPE_IDENTITY();

        -- 3. Lay RoleID cua Customer
        DECLARE @RoleID INT;
        SELECT @RoleID = RoleID FROM Role WHERE RoleName = 'Customer' AND RoleStatus = 'Active';

        IF @RoleID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 57002, 'sp_RegisterUser: Role Customer khong ton tai hoac khong Active.', 1;
        END

        -- 4. Gan Role cho User
        INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
        VALUES (@NewUserID, @RoleID, 'Active');

        -- 5. Ghi AuditRecord (BP15)
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@NewUserID, 'ACCOUNT_REGISTERED', 'UserAccount',
             CAST(@NewUserID AS VARCHAR(64)), 'INSERT',
             SYSDATETIME(),
             '{"Username":"' + @Username + '","Role":"Customer"}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
