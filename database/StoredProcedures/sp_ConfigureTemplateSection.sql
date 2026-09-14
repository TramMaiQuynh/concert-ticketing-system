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
    @ZoneID           INT,
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
        DECLARE @VersionStatus VARCHAR(32), @CanvasWidth INT, @CanvasHeight INT, @TemplateVenueID INT, @VenueTemplateVersionID INT;
        SELECT @VersionStatus = vtv.VersionStatus, @CanvasWidth = f.CanvasWidth, @CanvasHeight = f.CanvasHeight,
               @TemplateVenueID = vt.VenueID, @VenueTemplateVersionID = vtv.VenueTemplateVersionID
        FROM TemplateFloor f WITH (UPDLOCK, HOLDLOCK)
        JOIN VenueTemplateVersion vtv WITH (UPDLOCK, HOLDLOCK) ON vtv.VenueTemplateVersionID = f.VenueTemplateVersionID
        JOIN VenueTemplate vt ON vt.VenueTemplateID = vtv.VenueTemplateID
        WHERE f.TemplateFloorID = @TemplateFloorID;

        IF @VersionStatus IS NULL
            THROW 60082, 'sp_ConfigureTemplateSection: TemplateFloor khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60083, 'sp_ConfigureTemplateSection: Chi sua duoc Section cua version dang Draft.', 1;

        -- Section la hinh chieu cua CHINH MOT Zone vat ly. Rang buoc nay ngan
        -- viec ve mot khu cua venue khac, hoac lien ket den khu da retired.
        IF NOT EXISTS (
            SELECT 1
            FROM Zone z WITH (UPDLOCK, HOLDLOCK)
            WHERE z.ZoneID = @ZoneID
              AND z.VenueID = @TemplateVenueID
              AND z.ZoneStatus = 'Active'
        )
            THROW 60095, 'sp_ConfigureTemplateSection: Zone khong ton tai, khong thuoc Venue cua template, hoac da Retired.', 1;

        -- Mot Zone chi co mot Section trong mot version. Neu can ve nhiều manh
        -- cua cung khu, mo rong GeometryJson thanh multi-path trong mot Section;
        -- khong tao them identity Section de tranh lap ghe/inventory.
        IF EXISTS (
            SELECT 1
            FROM TemplateSection other
            JOIN TemplateFloor otherFloor ON otherFloor.TemplateFloorID = other.TemplateFloorID
            WHERE otherFloor.VenueTemplateVersionID = @VenueTemplateVersionID
              AND other.ZoneID = @ZoneID
              AND other.TemplateSectionID <> ISNULL(@TemplateSectionID, -1)
        )
            THROW 60096, 'sp_ConfigureTemplateSection: Zone da duoc gan cho mot Section khac trong version nay.', 1;

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

            INSERT INTO TemplateSection (TemplateFloorID, ZoneID, SectionKey, SectionName, GeometryJson)
            VALUES (@TemplateFloorID, @ZoneID, @SectionKey, @SectionName, @GeometryJson);

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

            -- Khong duoc doi ZoneID cua mot Section DA CO GHE: moi TemplateSeat con
            -- (them qua sp_ConfigureTemplateSeat) da duoc xac nhan thuoc DUNG ZoneID
            -- CU cua Section tai thoi diem tao (loi 60112 neu khong khop) — doi ZoneID
            -- sau do se de lai cac ghe do tro toi mot Zone ma chung khong con thuoc ve,
            -- ma khong co dau hieu gi bao. Vi du that: Section tro Zone VIP chua Seat
            -- VIP-01, doi Section sang Zone Balcony — Seat VIP-01 van "nam trong" mot
            -- Section gio dai dien cho Balcony. Section rong (chua co TemplateSeat)
            -- van doi ZoneID tu do duoc, dung 1 Zone / 1 Section moi phia tren.
            IF EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSectionID = @TemplateSectionID)
               AND @ZoneID <> (SELECT ZoneID FROM TemplateSection WHERE TemplateSectionID = @TemplateSectionID)
                THROW 60098, 'sp_ConfigureTemplateSection: Khong the doi Zone cua Section da co ghe — xoa ghe truoc hoac giu nguyen Zone.', 1;

            UPDATE TemplateSection
            SET ZoneID = @ZoneID, SectionKey = @SectionKey, SectionName = @SectionName, GeometryJson = @GeometryJson
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
