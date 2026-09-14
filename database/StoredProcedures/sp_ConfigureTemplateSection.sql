-- ============================================================
-- sp_ConfigureTemplateSection (StagePass D.4)
-- Tao moi/cap nhat mot TemplateSection (khu ghe, tuong duong Zone nhung
-- KHONG gioi han hinh chu nhat) trong mot TemplateFloor. Chi Admin.
--
-- Khac Zone (co ZoneLevel de phan biet cac tang chong hinh chieu), moi
-- TemplateFloor DA LA mot tang/canvas rieng — nen MOI Section tren CUNG mot
-- Floor deu loai tru lan nhau, khong can loc theo muc nhu sp_CreateZone.
--
-- Khoa UPDLOCK+HOLDLOCK tren dong TemplateFloor — cung tai nguyen ma
-- sp_ConfigureTemplateObject dang khoa — de hai SP nay tuan tu hoa voi nhau
-- khi cung sua du lieu hinh hoc cua MOT floor (tranh doc du lieu cu trong
-- luc kiem tra va cham, dung ly do sp_CreateZone da neu cho Venue).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureTemplateSection
(
    @ActorUserID      INT,
    @TemplateFloorID  INT,
    @SectionKey       VARCHAR(64),
    @SectionName      NVARCHAR(255) = NULL,
    @GeometryJson     NVARCHAR(MAX),
    @TemplateSectionID INT = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60081, 'sp_ConfigureTemplateSection: Chi Admin duoc cau hinh TemplateSection.', 1;

        -- UPDLOCK+HOLDLOCK tren CA HAI dong (TemplateFloor VA VenueTemplateVersion)
        -- — xem giai thich chi tiet trong sp_ConfigureTemplateObject.sql: da
        -- tai hien duoc bang thuc nghiem (2 phien song song, WAITFOR mo phong
        -- khoang ho) rang chi khoa Floor la KHONG du, sp_PublishVenueTemplateVersion
        -- van chen vao va Publish thanh cong giua chung, khien Section moi van
        -- duoc them vao mot version DA Published — pha vo bat bien "Published
        -- la bat bien".
        DECLARE @VersionStatus VARCHAR(32), @CanvasWidth INT, @CanvasHeight INT;
        SELECT @VersionStatus = vtv.VersionStatus, @CanvasWidth = f.CanvasWidth, @CanvasHeight = f.CanvasHeight
        FROM TemplateFloor f WITH (UPDLOCK, HOLDLOCK)
        JOIN VenueTemplateVersion vtv WITH (UPDLOCK, HOLDLOCK) ON vtv.VenueTemplateVersionID = f.VenueTemplateVersionID
        WHERE f.TemplateFloorID = @TemplateFloorID;

        IF @VersionStatus IS NULL
            THROW 60082, 'sp_ConfigureTemplateSection: TemplateFloor khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60083, 'sp_ConfigureTemplateSection: Chi sua duoc Section cua version dang Draft.', 1;

        IF ISNULL(@SectionKey, '') = ''
            THROW 60084, 'sp_ConfigureTemplateSection: SectionKey khong duoc de trong.', 1;

        IF dbo.fn_TemplateGeometryIsStructurallyValid(@GeometryJson) <> 1
            THROW 60085, 'sp_ConfigureTemplateSection: GeometryJson khong dung cau truc (xem quy uoc v1 trong TemplateSection.sql).', 1;

        IF dbo.fn_TemplateGeometryIsConvex(@GeometryJson) <> 1
            THROW 60086, 'sp_ConfigureTemplateSection: Hinh khong loi — StagePass chi ho tro va cham chinh xac cho hinh loi.', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.fn_TemplateGeometryToPoints(@GeometryJson) pt
            WHERE pt.X < 0 OR pt.X > @CanvasWidth OR pt.Y < 0 OR pt.Y > @CanvasHeight
        )
            THROW 60087, 'sp_ConfigureTemplateSection: Section nam ngoai canvas cua Floor.', 1;

        IF EXISTS (
            SELECT 1 FROM TemplateObject o
            WHERE o.TemplateFloorID = @TemplateFloorID
              AND o.ObjectType = 'Stage'
              AND dbo.fn_TemplateGeometryOverlaps(@GeometryJson, o.GeometryJson) = 1
        )
            THROW 60088, 'sp_ConfigureTemplateSection: Section khong duoc chong len San khau.', 1;

        IF EXISTS (
            SELECT 1 FROM TemplateSection s
            WHERE s.TemplateFloorID = @TemplateFloorID
              AND s.TemplateSectionID <> ISNULL(@TemplateSectionID, -1)
              AND dbo.fn_TemplateGeometryOverlaps(@GeometryJson, s.GeometryJson) = 1
        )
            THROW 60089, 'sp_ConfigureTemplateSection: Section chong len mot Section khac cung Floor.', 1;

        IF @TemplateSectionID IS NULL OR @TemplateSectionID <= 0
        BEGIN
            IF EXISTS (SELECT 1 FROM TemplateSection WHERE TemplateFloorID = @TemplateFloorID AND SectionKey = @SectionKey)
                THROW 60090, 'sp_ConfigureTemplateSection: SectionKey da ton tai trong Floor nay.', 1;

            INSERT INTO TemplateSection (TemplateFloorID, SectionKey, SectionName, GeometryJson)
            VALUES (@TemplateFloorID, @SectionKey, @SectionName, @GeometryJson);

            SET @TemplateSectionID = SCOPE_IDENTITY();

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_SECTION_CREATED', 'TemplateSection', CAST(@TemplateSectionID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                    '{"TemplateFloorID":' + CAST(@TemplateFloorID AS VARCHAR(20)) + ',"SectionKey":"' + STRING_ESCAPE(@SectionKey, 'json') + '"}');
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM TemplateSection WHERE TemplateSectionID = @TemplateSectionID AND TemplateFloorID = @TemplateFloorID)
                THROW 60091, 'sp_ConfigureTemplateSection: TemplateSectionID khong thuoc TemplateFloor nay.', 1;

            IF EXISTS (SELECT 1 FROM TemplateSection WHERE TemplateFloorID = @TemplateFloorID AND SectionKey = @SectionKey AND TemplateSectionID <> @TemplateSectionID)
                THROW 60090, 'sp_ConfigureTemplateSection: SectionKey da ton tai trong Floor nay.', 1;

            UPDATE TemplateSection
            SET SectionKey = @SectionKey, SectionName = @SectionName, GeometryJson = @GeometryJson
            WHERE TemplateSectionID = @TemplateSectionID;

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_SECTION_UPDATED', 'TemplateSection', CAST(@TemplateSectionID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"SectionKey":"' + STRING_ESCAPE(@SectionKey, 'json') + '"}');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
