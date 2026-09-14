-- ============================================================
-- sp_CreateVenueTemplate (StagePass D.2)
-- Tao mot VenueTemplate moi (identity on dinh cho MOT cach bo tri cua Venue,
-- vd 'Theatre', 'End-stage'). Chi Admin — cung quyen voi sp_CreateVenue/
-- sp_CreateZone, vi day la du lieu ha tang dia diem, khong phai du lieu
-- nghiep vu cua Organizer.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateVenueTemplate
(
    @ActorUserID       INT,
    @VenueID           INT,
    @TemplateName      NVARCHAR(255),
    @NewVenueTemplateID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60001, 'sp_CreateVenueTemplate: Chi Admin duoc tao VenueTemplate.', 1;

        IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID = @VenueID)
            THROW 60002, 'sp_CreateVenueTemplate: Venue khong ton tai.', 1;

        IF ISNULL(@TemplateName, '') = ''
            THROW 60003, 'sp_CreateVenueTemplate: TemplateName khong duoc de trong.', 1;

        IF EXISTS (SELECT 1 FROM VenueTemplate WHERE VenueID = @VenueID AND TemplateName = @TemplateName)
            THROW 60004, 'sp_CreateVenueTemplate: Ten template da ton tai trong Venue nay.', 1;

        INSERT INTO VenueTemplate (VenueID, TemplateName, TemplateStatus, CreatedTimestamp, UpdatedTimestamp)
        VALUES (@VenueID, @TemplateName, 'Active', SYSDATETIME(), SYSDATETIME());

        SET @NewVenueTemplateID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'VENUE_TEMPLATE_CREATED', 'VenueTemplate', CAST(@NewVenueTemplateID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"VenueID":' + CAST(@VenueID AS VARCHAR(20)) + ',"TemplateName":"' + STRING_ESCAPE(@TemplateName, 'json') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
