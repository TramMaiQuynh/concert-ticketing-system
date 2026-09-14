-- ============================================================
-- sp_DeleteTemplateFloor (StagePass D.4)
-- Xoa MOT TemplateFloor (va toan bo Object/Section/Seat ben trong no) khoi
-- VenueTemplateVersion — cung ly do voi 3 SP xoa StagePass con lai. Chi
-- Admin, chi xoa duoc khi version dang Draft. Xoa theo dung thu tu con
-- truoc cha (Seat -> Section, Object, roi Floor) trong CUNG transaction.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_DeleteTemplateFloor
(
    @ActorUserID     INT,
    @TemplateFloorID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60052, 'sp_DeleteTemplateFloor: Chi Admin duoc xoa TemplateFloor.', 1;

        DECLARE @VersionStatus VARCHAR(32);
        SELECT @VersionStatus = VersionStatus
        FROM VenueTemplateVersion vtv WITH (UPDLOCK, HOLDLOCK)
        WHERE vtv.VenueTemplateVersionID = (SELECT VenueTemplateVersionID FROM TemplateFloor WHERE TemplateFloorID = @TemplateFloorID);

        IF @VersionStatus IS NULL
            THROW 60053, 'sp_DeleteTemplateFloor: TemplateFloor khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60054, 'sp_DeleteTemplateFloor: Chi xoa duoc Floor cua version dang Draft.', 1;

        DELETE ts
        FROM TemplateSeat ts
        JOIN TemplateSection s ON s.TemplateSectionID = ts.TemplateSectionID
        WHERE s.TemplateFloorID = @TemplateFloorID;

        DELETE FROM TemplateSection WHERE TemplateFloorID = @TemplateFloorID;
        DELETE FROM TemplateObject WHERE TemplateFloorID = @TemplateFloorID;
        DELETE FROM TemplateFloor WHERE TemplateFloorID = @TemplateFloorID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'TEMPLATE_FLOOR_DELETED', 'TemplateFloor', CAST(@TemplateFloorID AS VARCHAR(64)), 'DELETE', SYSDATETIME(), NULL);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
