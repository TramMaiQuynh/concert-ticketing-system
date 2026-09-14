-- ============================================================
-- sp_DeleteTemplateObject (StagePass D.4)
-- Xoa MOT TemplateObject (san khau, loi di, vat trang tri...) khoi Floor —
-- cung ly do voi sp_DeleteTemplateSeat.sql: sp_ConfigureTemplateObject
-- chi tao-hoac-sua, thieu duong xoa rieng le. Chi Admin, chi xoa duoc khi
-- version cha dang Draft.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_DeleteTemplateObject
(
    @ActorUserID      INT,
    @TemplateObjectID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60069, 'sp_DeleteTemplateObject: Chi Admin duoc xoa TemplateObject.', 1;

        DECLARE @VersionStatus VARCHAR(32);
        SELECT @VersionStatus = vtv.VersionStatus
        FROM TemplateObject o
        JOIN TemplateFloor f ON f.TemplateFloorID = o.TemplateFloorID
        JOIN VenueTemplateVersion vtv WITH (UPDLOCK, HOLDLOCK) ON vtv.VenueTemplateVersionID = f.VenueTemplateVersionID
        WHERE o.TemplateObjectID = @TemplateObjectID;

        IF @VersionStatus IS NULL
            THROW 60070, 'sp_DeleteTemplateObject: TemplateObject khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60071, 'sp_DeleteTemplateObject: Chi xoa duoc Object cua version dang Draft.', 1;

        DELETE FROM TemplateObject WHERE TemplateObjectID = @TemplateObjectID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'TEMPLATE_OBJECT_DELETED', 'TemplateObject', CAST(@TemplateObjectID AS VARCHAR(64)), 'DELETE', SYSDATETIME(), NULL);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
