-- ============================================================
-- sp_PublishVenueTemplateVersion (StagePass D.2)
-- Chuyen mot VenueTemplateVersion tu Draft sang Published — tu day tro di
-- BAT BIEN, khong SP nao duoc sua hinh hoc cua no nua (xem comment
-- VenueTemplateVersion.sql). Chi Admin.
--
-- Khong cho publish mot version rong: mot template khong co ghe nao khong
-- dung duoc de ban ve, va neu cho phep se chi phat hien ra luc Organizer
-- da chon no cho Concert that (loi muon hon nhieu, kho truy vet hon).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_PublishVenueTemplateVersion
(
    @ActorUserID           INT,
    @VenueTemplateVersionID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60021, 'sp_PublishVenueTemplateVersion: Chi Admin duoc publish VenueTemplateVersion.', 1;

        DECLARE @VersionStatus VARCHAR(32);
        -- UPDLOCK: tranh hai request publish cung luc cung version (dua nhau
        -- qua kiem tra trang thai roi ca hai cung UPDATE).
        SELECT @VersionStatus = VersionStatus FROM VenueTemplateVersion WITH (UPDLOCK, HOLDLOCK)
        WHERE VenueTemplateVersionID = @VenueTemplateVersionID;

        IF @VersionStatus IS NULL
            THROW 60022, 'sp_PublishVenueTemplateVersion: VenueTemplateVersion khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60023, 'sp_PublishVenueTemplateVersion: Chi publish duoc version dang Draft.', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM TemplateFloor f
            JOIN TemplateSection s ON s.TemplateFloorID = f.TemplateFloorID
            JOIN TemplateSeat ts ON ts.TemplateSectionID = s.TemplateSectionID
            WHERE f.VenueTemplateVersionID = @VenueTemplateVersionID
        )
            THROW 60024, 'sp_PublishVenueTemplateVersion: Version chua co ghe nao (can it nhat mot Floor/Section/Seat).', 1;

        UPDATE VenueTemplateVersion
        SET VersionStatus = 'Published', PublishedTimestamp = SYSDATETIME()
        WHERE VenueTemplateVersionID = @VenueTemplateVersionID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'VENUE_TEMPLATE_VERSION_PUBLISHED', 'VenueTemplateVersion', CAST(@VenueTemplateVersionID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"VersionStatus":"Published"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
