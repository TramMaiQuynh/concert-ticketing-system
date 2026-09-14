-- ============================================================
-- sp_DeleteTemplateSection (StagePass D.4)
-- Xoa MOT TemplateSection (va toan bo TemplateSeat ben trong no) khoi
-- Floor — cung ly do voi sp_DeleteTemplateSeat.sql/sp_DeleteTemplateObject.sql.
-- Chi Admin, chi xoa duoc khi version cha dang Draft. Xoa Seat con truoc
-- Section cha trong CUNG transaction (khong dua vao ON DELETE CASCADE —
-- schema nay khong dung CASCADE o dau ca, xem quy uoc chung cua du an).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_DeleteTemplateSection
(
    @ActorUserID       INT,
    @TemplateSectionID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60092, 'sp_DeleteTemplateSection: Chi Admin duoc xoa TemplateSection.', 1;

        DECLARE @VersionStatus VARCHAR(32);
        SELECT @VersionStatus = vtv.VersionStatus
        FROM TemplateSection s
        JOIN TemplateFloor f ON f.TemplateFloorID = s.TemplateFloorID
        JOIN VenueTemplateVersion vtv WITH (UPDLOCK, HOLDLOCK) ON vtv.VenueTemplateVersionID = f.VenueTemplateVersionID
        WHERE s.TemplateSectionID = @TemplateSectionID;

        IF @VersionStatus IS NULL
            THROW 60093, 'sp_DeleteTemplateSection: TemplateSection khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60094, 'sp_DeleteTemplateSection: Chi xoa duoc Section cua version dang Draft.', 1;

        DELETE FROM TemplateSeat WHERE TemplateSectionID = @TemplateSectionID;
        DELETE FROM TemplateSection WHERE TemplateSectionID = @TemplateSectionID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'TEMPLATE_SECTION_DELETED', 'TemplateSection', CAST(@TemplateSectionID AS VARCHAR(64)), 'DELETE', SYSDATETIME(), NULL);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
