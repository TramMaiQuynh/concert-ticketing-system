-- ============================================================
-- sp_UpdateVenueTemplate (StagePass D.2)
-- Doi ten va/hoac trang thai Active/Archived cua mot VenueTemplate. Chi
-- Admin. Phat hien thieu khi soat lai toan bo tang SP: sp_CreateVenueTemplate
-- co nhung khong co SP sua — mot template go sai ten hoac can "nghi huu"
-- (khong con dung de tao version moi, nhung van giu lai cho lich su cac
-- version da Published) se khong co duong nao thuc hien duoc, du bang da
-- co san cot TemplateStatus va comment VenueTemplate.sql da mo ta ro hai
-- trang thai nay tu dau.
--
-- Doi ten khong anh huong Version/Floor/Section/Seat da co (chung tham
-- chieu VenueTemplateID, khong tham chieu ten). Archived KHONG khoa duoc
-- version da Published (chung van con nguyen, chi la template khong con
-- xuat hien cho lua chon TAO MOI — dung nhu comment goc: "khong hien ra cho
-- lua chon moi").
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateVenueTemplate
(
    @ActorUserID      INT,
    @VenueTemplateID  INT,
    @TemplateName     NVARCHAR(255) = NULL,   -- NULL = giu nguyen
    @TemplateStatus   VARCHAR(32)   = NULL    -- NULL = giu nguyen; 'Active' | 'Archived'
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60005, 'sp_UpdateVenueTemplate: Chi Admin duoc sua VenueTemplate.', 1;

        DECLARE @VenueID INT, @CurrentName NVARCHAR(255), @CurrentStatus VARCHAR(32);
        SELECT @VenueID = VenueID, @CurrentName = TemplateName, @CurrentStatus = TemplateStatus
        FROM VenueTemplate WITH (UPDLOCK, HOLDLOCK)
        WHERE VenueTemplateID = @VenueTemplateID;

        IF @VenueID IS NULL
            THROW 60006, 'sp_UpdateVenueTemplate: VenueTemplate khong ton tai.', 1;

        IF @TemplateStatus IS NOT NULL AND @TemplateStatus NOT IN ('Active', 'Archived')
            THROW 60007, 'sp_UpdateVenueTemplate: TemplateStatus phai la Active hoac Archived.', 1;

        DECLARE @NewName NVARCHAR(255) = ISNULL(@TemplateName, @CurrentName);
        DECLARE @NewStatus VARCHAR(32) = ISNULL(@TemplateStatus, @CurrentStatus);

        IF ISNULL(@NewName, '') = ''
            THROW 60008, 'sp_UpdateVenueTemplate: TemplateName khong duoc de trong.', 1;

        IF @TemplateName IS NOT NULL AND EXISTS (
            SELECT 1 FROM VenueTemplate WHERE VenueID = @VenueID AND TemplateName = @NewName AND VenueTemplateID <> @VenueTemplateID
        )
            THROW 60009, 'sp_UpdateVenueTemplate: Ten template da ton tai trong Venue nay.', 1;

        UPDATE VenueTemplate
        SET TemplateName = @NewName, TemplateStatus = @NewStatus, UpdatedTimestamp = SYSDATETIME()
        WHERE VenueTemplateID = @VenueTemplateID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'VENUE_TEMPLATE_UPDATED', 'VenueTemplate', CAST(@VenueTemplateID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"TemplateName":"' + STRING_ESCAPE(@NewName, 'json') + '","TemplateStatus":"' + @NewStatus + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
