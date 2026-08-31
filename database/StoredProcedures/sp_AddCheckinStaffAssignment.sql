-- ============================================================
-- sp_AddCheckinStaffAssignment (BP9 / BR39 / FR51)
-- Gan Check-in Staff cho danh sach Concert. Chi Admin.
-- Khong gan tai khoan he thong.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AddCheckinStaffAssignment
(
    @ActorUserID   INT,
    @StaffUserID   INT,
    @ConcertIDs    NVARCHAR(MAX)  -- CSV
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
            THROW 59001, 'sp_AddCheckinStaffAssignment: Chi Admin thuc hien duoc.', 1;

        IF NOT EXISTS (SELECT 1 FROM UserAccount WHERE UserID = @StaffUserID AND Username <> 'system')
            THROW 59002, 'sp_AddCheckinStaffAssignment: Staff khong ton tai.', 1;

        -- Phai co Role Check-in Staff
        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @StaffUserID AND r.RoleName = 'Check-in Staff' AND ura.AssignmentStatus = 'Active')
            THROW 59003, 'sp_AddCheckinStaffAssignment: User khong co role Check-in Staff.', 1;

        DECLARE @ConcertIdList TABLE (ConcertID INT NOT NULL PRIMARY KEY);
        INSERT INTO @ConcertIdList (ConcertID)
        SELECT DISTINCT CAST(value AS INT)
        FROM STRING_SPLIT(@ConcertIDs, ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        IF NOT EXISTS (SELECT 1 FROM @ConcertIdList)
            THROW 59004, 'sp_AddCheckinStaffAssignment: Danh sach Concert rong.', 1;

        -- Chi INSERT nhung cap chua ton tai
        INSERT INTO CheckinStaffAssignment (UserID, ConcertID, AssignedTimestamp)
        SELECT @StaffUserID, c.ConcertID, SYSDATETIME()
        FROM @ConcertIdList c
        WHERE c.ConcertID IN (SELECT ConcertID FROM Concert)
          AND NOT EXISTS (SELECT 1 FROM CheckinStaffAssignment x
                          WHERE x.UserID = @StaffUserID AND x.ConcertID = c.ConcertID);

        DECLARE @Count INT = @@ROWCOUNT;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'CHECKIN_STAFF_ASSIGNED', 'CheckinStaffAssignment',
                CAST(@StaffUserID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"Assigned":' + CAST(@Count AS VARCHAR) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO