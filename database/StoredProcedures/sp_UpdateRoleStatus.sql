-- ============================================================
-- sp_UpdateRoleStatus (BP12 / BR52 / §12.3.2 / §24.4)
-- Mo hoac dong kha nang PHAN CONG cua mot Role. CHI Admin.
--
-- Ly do SP nay ton tai - dung mach voi sp_UpdateVenue/sp_UpdateZone/sp_UpdateSeat:
-- §12.3.2 dinh nghia thuoc tinh "Trang thai vai tro" voi muc dich rat cu the -
-- "cho biet Vai tro co dang duoc phep phan cong hay khong" - va sp_AssignRole DA
-- cai dat ve DOC cua cong nay (`WHERE RoleName = @RoleName AND RoleStatus =
-- 'Active'`). Nhung truoc day KHONG co bat ky duong ghi nao dat duoc 'Inactive':
-- SeedData chi INSERT 'Active', khong SP/trigger nao UPDATE bang Role. Nghia la
-- mot nang luc da duoc dac ta va da co lop kiem tra, nhung khong ai kich hoat
-- duoc - dung dinh nghia "chu chet" ma §24.4 cam.
--
-- PHAM VI TAC DONG - doc ky truoc khi dung:
-- Dat Role ve 'Inactive' chi DONG DAU VAO, tuc khong ai duoc phan cong Role do nua.
-- No KHONG thu hoi quyen cua nhung nguoi DANG giu Role. Do dung nguyen van §12.3.2
-- ("duoc phep phan cong"), va vi thu hoi da co duong rieng: sp_AssignRole voi
-- @GrantOrRevoke = 'Revoke' dat UserRoleAssignment.AssignmentStatus = 'Revoked'.
-- Gop hai viec nay lam mot se khien mot thao tac "tam dung tuyen dung" bong nhien
-- vo hieu hoa toan bo nhan su dang lam viec - hau qua khong ai yeu cau.
--
-- HAI ROLE KHONG THE DONG (guard 59904). Nguyen tac: Role nao ma CHINH HE THONG
-- phu thuoc de van hanh thi khong duoc dong dau vao.
--   * Customer  - sp_RegisterUser tu gan Role nay cho MOI tai khoan moi. Dong lai
--                 la khoa toan bo viec dang ky, khong con ai vao duoc he thong.
--   * Admin     - UAI01 doi luon con it nhat mot Admin Active. Neu Admin khong the
--                 phan cong duoc nua, den luc so Admin hien huu can kiet thi he
--                 thong vinh vien khong the co lai quan tri vien - mot cai bay
--                 khong loi thoat.
-- Organizer va Check-in Staff thi khac han: chung chi duoc cap bang quyet dinh cua
-- Admin, nen tam dung cap moi la thao tac van hanh binh thuong va an toan.
-- Day cung la thong le cua cac he quan tri danh tinh thuc te (Okta, Azure Entra):
-- vai tro dung san cua he thong khong the vo hieu hoa, chi vai tro do nguoi dung
-- tu tao moi duoc.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateRoleStatus
(
    @ActorUserID INT,
    @RoleName    NVARCHAR(255),
    @RoleStatus  VARCHAR(32)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Chi Admin (BR52). Cung khuon kiem tra voi sp_UpdateVenue/sp_AssignRole.
        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura
                       JOIN   Role r ON r.RoleID = ura.RoleID
                       JOIN   UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE  ura.UserID = @ActorUserID
                         AND  r.RoleName = 'Admin'
                         AND  ura.AssignmentStatus = 'Active'
                         AND  uaAdm.AccountStatus  = 'Active')
            THROW 59901, 'sp_UpdateRoleStatus: Chi Admin duoc doi trang thai Role.', 1;

        -- 2. Mien gia tri (§18.4.1 Role Status)
        IF @RoleStatus NOT IN ('Active', 'Inactive')
            THROW 59903, 'sp_UpdateRoleStatus: RoleStatus phai la Active hoac Inactive.', 1;

        -- 3. Role phai ton tai. UPDLOCK de tuan tu hoa hai Admin doi cung mot Role.
        DECLARE @RoleID INT, @OldStatus VARCHAR(32);
        SELECT @RoleID = RoleID, @OldStatus = RoleStatus
        FROM   Role WITH (UPDLOCK)
        WHERE  RoleName = @RoleName;

        IF @RoleID IS NULL
            THROW 59902, 'sp_UpdateRoleStatus: Role khong ton tai.', 1;

        -- 4. Guard: khong dong dau vao cua Role ma he thong phu thuoc (xem dau file).
        IF @RoleStatus = 'Inactive' AND @RoleName IN ('Customer', 'Admin')
            THROW 59904, 'sp_UpdateRoleStatus: Khong the ngung phan cong Role Customer hoac Admin - he thong phu thuoc vao chung de dang ky tai khoan va de luon con quan tri vien.', 1;

        -- 5. No-op la hop le va im lang: goi lai cung mot trang thai khong phai loi.
        IF @OldStatus = @RoleStatus
        BEGIN
            COMMIT TRANSACTION;
            RETURN;
        END

        UPDATE Role SET RoleStatus = @RoleStatus WHERE RoleID = @RoleID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'ROLE_STATUS_UPDATED', 'Role', CAST(@RoleID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"RoleStatus":"' + @OldStatus + '"}',
                '{"RoleStatus":"' + @RoleStatus + '","RoleName":"' + STRING_ESCAPE(@RoleName, 'json') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
