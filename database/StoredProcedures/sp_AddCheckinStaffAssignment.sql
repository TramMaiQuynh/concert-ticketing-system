-- ============================================================
-- sp_AddCheckinStaffAssignment (BP9 / BR39 / FR51)
-- Gan Check-in Staff cho danh sach Concert. Chi Admin.
-- Khong gan tai khoan he thong.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AddCheckinStaffAssignment
(
    @ActorUserID   INT,
    @StaffUserID   INT,
    @ConcertIDs    NVARCHAR(MAX),  -- CSV
    -- BR39/FR51: phan cong VA thu hoi phan cong. Truoc day chi co duong gan
    -- ('Active'), nen 'Revoked' trong CHK_StaffAssignment_Status khong the dat toi -
    -- mot nhan vien nghi viec van check-in duoc mai mai, du sp_CheckInTicket da loc
    -- `AssignmentStatus = 'Active'` va thong bao loi cua no da noi den viec thu hoi.
    -- Doi xung voi @GrantOrRevoke cua sp_AssignRole.
    @AssignmentStatus VARCHAR(32) = 'Active'
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
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

        IF @AssignmentStatus NOT IN ('Active', 'Revoked')
            THROW 59005, 'sp_AddCheckinStaffAssignment: AssignmentStatus phai la Active hoac Revoked.', 1;

        DECLARE @Count INT = 0;

        -- Cap nhat cac cap da ton tai ve dung trang thai yeu cau (gan lai / thu hoi)
        UPDATE csa
        SET    csa.AssignmentStatus = @AssignmentStatus,
               csa.AssignedTimestamp = CASE WHEN @AssignmentStatus = 'Active'
                                            THEN SYSDATETIME() ELSE csa.AssignedTimestamp END,
               -- Gan lai (Revoked -> Active) thi nguoi cap quyen moi la nguoi chiu
               -- trach nhiem cho quyen dang co hieu luc. Thu hoi thi giu nguyen -
               -- cot nay tra loi "ai da cap", va cau tra loi do khong doi khi quyen
               -- bi go bo. Doi xung y het cach AssignedTimestamp duoc xu ly.
               csa.AssignedByUserID = CASE WHEN @AssignmentStatus = 'Active'
                                           THEN @ActorUserID ELSE csa.AssignedByUserID END
        FROM   CheckinStaffAssignment csa
        JOIN   @ConcertIdList c ON c.ConcertID = csa.ConcertID
        WHERE  csa.UserID = @StaffUserID
          AND  csa.AssignmentStatus <> @AssignmentStatus;

        SET @Count = @@ROWCOUNT;

        -- Chi INSERT nhung cap chua ton tai, va chi khi dang GAN (thu hoi mot phan cong
        -- chua bao gio ton tai la vo nghia - khong tao ban ghi 'Revoked' rong).
        IF @AssignmentStatus = 'Active'
        BEGIN
            INSERT INTO CheckinStaffAssignment (UserID, ConcertID, AssignedByUserID, AssignedTimestamp, AssignmentStatus)
            SELECT @StaffUserID, c.ConcertID, @ActorUserID, SYSDATETIME(), 'Active'
            FROM @ConcertIdList c
            WHERE c.ConcertID IN (SELECT ConcertID FROM Concert)
              AND NOT EXISTS (SELECT 1 FROM CheckinStaffAssignment x
                              WHERE x.UserID = @StaffUserID AND x.ConcertID = c.ConcertID);

            SET @Count = @Count + @@ROWCOUNT;
        END

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID,
                CASE WHEN @AssignmentStatus = 'Active' THEN 'CHECKIN_STAFF_ASSIGNED' ELSE 'CHECKIN_STAFF_REVOKED' END,
                'CheckinStaffAssignment',
                CAST(@StaffUserID AS VARCHAR(64)),
                CASE WHEN @AssignmentStatus = 'Active' THEN 'INSERT' ELSE 'UPDATE' END,
                SYSDATETIME(),
                '{"AssignmentStatus":"' + @AssignmentStatus + '","Affected":' + CAST(@Count AS VARCHAR) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO