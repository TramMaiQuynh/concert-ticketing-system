-- ============================================================
-- sp_ConfigureTemplateFloor (StagePass D.4)
-- Tao moi (khi @TemplateFloorID = NULL) hoac cap nhat mot TemplateFloor
-- trong mot VenueTemplateVersion — dung khuon "mot SP tao-hoac-sua theo
-- @ID nullable" cua sp_ConfigureTicketCategory. Chi Admin.
--
-- Chi sua duoc khi VenueTemplateVersion cha dang Draft — Published la bat
-- bien (xem comment VenueTemplateVersion.sql). Khoa UPDLOCK+HOLDLOCK tren
-- dong VenueTemplateVersion de tuan tu hoa cac SP StagePass D.4 khac cung
-- ghi vao cac Floor cua CUNG version (cung chien luoc sp_CreateZone khoa
-- dong Venue cha).
--
-- Neu thu nho CanvasWidth/Height, tu choi khi con TemplateObject/
-- TemplateSection nam ngoai bien moi — dung nguyen tac sp_ConfigureVenueMap
-- da ap dung cho Venue.MapWidth/Height ("chan thu nho mat phang duoi vung
-- khu dang chiem").
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureTemplateFloor
(
    @ActorUserID            INT,
    @VenueTemplateVersionID INT,
    @FloorKey               VARCHAR(64),
    @FloorName              NVARCHAR(255) = NULL,
    @FloorOrder             INT,
    @CanvasWidth            INT,
    @CanvasHeight           INT,
    @TemplateFloorID        INT = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60041, 'sp_ConfigureTemplateFloor: Chi Admin duoc cau hinh TemplateFloor.', 1;

        DECLARE @VersionStatus VARCHAR(32);
        SELECT @VersionStatus = VersionStatus FROM VenueTemplateVersion WITH (UPDLOCK, HOLDLOCK)
        WHERE VenueTemplateVersionID = @VenueTemplateVersionID;

        IF @VersionStatus IS NULL
            THROW 60042, 'sp_ConfigureTemplateFloor: VenueTemplateVersion khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60043, 'sp_ConfigureTemplateFloor: Chi sua duoc Floor cua version dang Draft.', 1;

        IF ISNULL(@FloorKey, '') = ''
            THROW 60044, 'sp_ConfigureTemplateFloor: FloorKey khong duoc de trong.', 1;

        IF @CanvasWidth <= 0 OR @CanvasHeight <= 0
            THROW 60045, 'sp_ConfigureTemplateFloor: CanvasWidth/CanvasHeight phai lon hon 0.', 1;

        IF @FloorOrder <= 0
            THROW 60046, 'sp_ConfigureTemplateFloor: FloorOrder phai lon hon 0.', 1;

        IF @TemplateFloorID IS NULL OR @TemplateFloorID <= 0
        BEGIN
            -- ── TAO MOI ──────────────────────────────────────────────────
            IF EXISTS (SELECT 1 FROM TemplateFloor WHERE VenueTemplateVersionID = @VenueTemplateVersionID AND FloorKey = @FloorKey)
                THROW 60047, 'sp_ConfigureTemplateFloor: FloorKey da ton tai trong version nay.', 1;

            IF EXISTS (SELECT 1 FROM TemplateFloor WHERE VenueTemplateVersionID = @VenueTemplateVersionID AND FloorOrder = @FloorOrder)
                THROW 60048, 'sp_ConfigureTemplateFloor: FloorOrder da duoc dung boi Floor khac trong version nay.', 1;

            INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorName, FloorOrder, CanvasWidth, CanvasHeight)
            VALUES (@VenueTemplateVersionID, @FloorKey, @FloorName, @FloorOrder, @CanvasWidth, @CanvasHeight);

            SET @TemplateFloorID = SCOPE_IDENTITY();

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_FLOOR_CREATED', 'TemplateFloor', CAST(@TemplateFloorID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                    '{"VenueTemplateVersionID":' + CAST(@VenueTemplateVersionID AS VARCHAR(20)) + ',"FloorKey":"' + STRING_ESCAPE(@FloorKey, 'json') + '"}');
        END
        ELSE
        BEGIN
            -- ── CAP NHAT ─────────────────────────────────────────────────
            IF NOT EXISTS (SELECT 1 FROM TemplateFloor WHERE TemplateFloorID = @TemplateFloorID AND VenueTemplateVersionID = @VenueTemplateVersionID)
                THROW 60049, 'sp_ConfigureTemplateFloor: TemplateFloorID khong thuoc VenueTemplateVersion nay.', 1;

            IF EXISTS (SELECT 1 FROM TemplateFloor WHERE VenueTemplateVersionID = @VenueTemplateVersionID AND FloorKey = @FloorKey AND TemplateFloorID <> @TemplateFloorID)
                THROW 60047, 'sp_ConfigureTemplateFloor: FloorKey da ton tai trong version nay.', 1;

            IF EXISTS (SELECT 1 FROM TemplateFloor WHERE VenueTemplateVersionID = @VenueTemplateVersionID AND FloorOrder = @FloorOrder AND TemplateFloorID <> @TemplateFloorID)
                THROW 60048, 'sp_ConfigureTemplateFloor: FloorOrder da duoc dung boi Floor khac trong version nay.', 1;

            IF EXISTS (
                SELECT 1 FROM TemplateObject o
                CROSS APPLY dbo.fn_TemplateGeometryToPoints(o.GeometryJson) pt
                WHERE o.TemplateFloorID = @TemplateFloorID
                  AND (pt.X < 0 OR pt.X > @CanvasWidth OR pt.Y < 0 OR pt.Y > @CanvasHeight)
            )
                THROW 60050, 'sp_ConfigureTemplateFloor: Khong the thu nho canvas — con TemplateObject nam ngoai bien moi.', 1;

            IF EXISTS (
                SELECT 1 FROM TemplateSection s
                CROSS APPLY dbo.fn_TemplateGeometryToPoints(s.GeometryJson) pt
                WHERE s.TemplateFloorID = @TemplateFloorID
                  AND (pt.X < 0 OR pt.X > @CanvasWidth OR pt.Y < 0 OR pt.Y > @CanvasHeight)
            )
                THROW 60051, 'sp_ConfigureTemplateFloor: Khong the thu nho canvas — con TemplateSection nam ngoai bien moi.', 1;

            UPDATE TemplateFloor
            SET FloorKey = @FloorKey, FloorName = @FloorName, FloorOrder = @FloorOrder,
                CanvasWidth = @CanvasWidth, CanvasHeight = @CanvasHeight
            WHERE TemplateFloorID = @TemplateFloorID;

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_FLOOR_UPDATED', 'TemplateFloor', CAST(@TemplateFloorID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"FloorKey":"' + STRING_ESCAPE(@FloorKey, 'json') + '"}');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
