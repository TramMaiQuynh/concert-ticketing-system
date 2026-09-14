-- ============================================================
-- sp_DeleteTemplateSeat (StagePass D.4)
-- Xoa MOT TemplateSeat khoi Section — sua thieu sot phat hien khi soat lai
-- toan bo tang SP: sp_ConfigureTemplateSeat chi tao-hoac-sua (theo @ID
-- nullable), khong co duong nao xoa RIENG mot ghe dat sai ma khong phai
-- xoa nguyen ca Draft (sp_DeleteVenueTemplateVersionDraft) — mot cong cu
-- soan thao that su khong bat nguoi dung ve lai tu dau chi vi mot ghe.
-- Chi Admin. Chi xoa duoc khi version cha dang Draft.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_DeleteTemplateSeat
(
    @ActorUserID    INT,
    @TemplateSeatID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60121, 'sp_DeleteTemplateSeat: Chi Admin duoc xoa TemplateSeat.', 1;

        -- UPDLOCK+HOLDLOCK tren VenueTemplateVersion — cung ly do da giai
        -- thich trong sp_ConfigureTemplateSeat: tranh sp_PublishVenueTemplateVersion
        -- chen vao giua luc xoa.
        DECLARE @VersionStatus VARCHAR(32);
        SELECT @VersionStatus = vtv.VersionStatus
        FROM TemplateSeat ts
        JOIN TemplateSection s ON s.TemplateSectionID = ts.TemplateSectionID
        JOIN TemplateFloor f ON f.TemplateFloorID = s.TemplateFloorID
        JOIN VenueTemplateVersion vtv WITH (UPDLOCK, HOLDLOCK) ON vtv.VenueTemplateVersionID = f.VenueTemplateVersionID
        WHERE ts.TemplateSeatID = @TemplateSeatID;

        IF @VersionStatus IS NULL
            THROW 60122, 'sp_DeleteTemplateSeat: TemplateSeat khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60123, 'sp_DeleteTemplateSeat: Chi xoa duoc Seat cua version dang Draft.', 1;

        DELETE FROM TemplateSeat WHERE TemplateSeatID = @TemplateSeatID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'TEMPLATE_SEAT_DELETED', 'TemplateSeat', CAST(@TemplateSeatID AS VARCHAR(64)), 'DELETE', SYSDATETIME(), NULL);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
