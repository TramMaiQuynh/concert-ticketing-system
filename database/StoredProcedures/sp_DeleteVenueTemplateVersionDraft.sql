-- ============================================================
-- sp_DeleteVenueTemplateVersionDraft (StagePass D.2)
-- Huy mot Draft chua publish, de Admin mo Draft khac (UIX_VTV_OneDraftPerTemplate
-- chi cho mot Draft/template). Chi xoa duoc Draft — theo dung bat bien ghi trong
-- comment VenueTemplateVersion.sql: khong co duong Draft -> Retired thang, vi
-- Retired nghia la "tung Published roi moi nghi", con Draft chua tung song nen
-- huy that (DELETE), khong "nghi huu" mot thu chua bao gio phuc vu ai.
-- Xoa cung ca cay con (Floor/Object/Section/Seat) trong cung transaction.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_DeleteVenueTemplateVersionDraft
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
            THROW 60031, 'sp_DeleteVenueTemplateVersionDraft: Chi Admin duoc huy Draft.', 1;

        DECLARE @VersionStatus VARCHAR(32);
        SELECT @VersionStatus = VersionStatus FROM VenueTemplateVersion WITH (UPDLOCK, HOLDLOCK)
        WHERE VenueTemplateVersionID = @VenueTemplateVersionID;

        IF @VersionStatus IS NULL
            THROW 60032, 'sp_DeleteVenueTemplateVersionDraft: VenueTemplateVersion khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60033, 'sp_DeleteVenueTemplateVersionDraft: Chi huy duoc version dang Draft (Published la bat bien).', 1;

        DELETE ts
        FROM TemplateSeat ts
        JOIN TemplateSection s ON s.TemplateSectionID = ts.TemplateSectionID
        JOIN TemplateFloor f ON f.TemplateFloorID = s.TemplateFloorID
        WHERE f.VenueTemplateVersionID = @VenueTemplateVersionID;

        DELETE s
        FROM TemplateSection s
        JOIN TemplateFloor f ON f.TemplateFloorID = s.TemplateFloorID
        WHERE f.VenueTemplateVersionID = @VenueTemplateVersionID;

        DELETE o
        FROM TemplateObject o
        JOIN TemplateFloor f ON f.TemplateFloorID = o.TemplateFloorID
        WHERE f.VenueTemplateVersionID = @VenueTemplateVersionID;

        DELETE FROM TemplateFloor WHERE VenueTemplateVersionID = @VenueTemplateVersionID;

        DELETE FROM VenueTemplateVersion WHERE VenueTemplateVersionID = @VenueTemplateVersionID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'VENUE_TEMPLATE_VERSION_DRAFT_DELETED', 'VenueTemplateVersion', CAST(@VenueTemplateVersionID AS VARCHAR(64)), 'DELETE', SYSDATETIME(), NULL);

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
