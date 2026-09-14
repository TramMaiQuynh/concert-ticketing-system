-- ============================================================
-- sp_CreateVenueTemplateVersion (StagePass D.2)
-- Tao mot VenueTemplateVersion moi o trang thai Draft cho mot VenueTemplate.
-- Chi Admin. Moi Template chi duoc mot Draft dang mo cung luc
-- (UIX_VTV_OneDraftPerTemplate) — kiem tra truoc va THROW loi sach thay vi
-- de INSERT vo tinh nem loi vi pham unique index tho.
--
-- @CopyFromVersionID (tuy chon): sao chep toan bo Floor/Object/Section/Seat
-- tu mot version CO SAN cua CUNG template sang Draft moi — dung cho nut
-- "Sao chep tu v_N" (docs/stagepass-architecture.md D.4), tranh bat Admin ve
-- lai tu dau khi chi doi mot vai khu. Dung MERGE...OUTPUT (ON 1=0 ep moi
-- dong nguon la NOT MATCHED) de vua INSERT vua lay duoc cap (OldID, NewID)
-- lam bang anh xa noi cac tang con — INSERT...SELECT thuan khong lam duoc
-- vi OUTPUT chi thay duoc cot cua dong VUA CHEN, khong thay duoc khoa nguon.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateVenueTemplateVersion
(
    @ActorUserID              INT,
    @VenueTemplateID          INT,
    @CopyFromVersionID        INT = NULL,
    @NewVenueTemplateVersionID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60011, 'sp_CreateVenueTemplateVersion: Chi Admin duoc tao VenueTemplateVersion.', 1;

        -- WITH (UPDLOCK, HOLDLOCK) tren dong VenueTemplate: khoa key-range de
        -- hai request tao Draft cho CUNG template khong cung tinh trung
        -- VersionNumber va cung vi pham UIX_VTV_OneDraftPerTemplate — cung
        -- khuon sp_CreateZone dang khoa dong Venue cha de tuan tu hoa cac
        -- giao dich con canh tranh.
        DECLARE @TemplateStatus VARCHAR(32);
        SELECT @TemplateStatus = TemplateStatus FROM VenueTemplate WITH (UPDLOCK, HOLDLOCK)
        WHERE VenueTemplateID = @VenueTemplateID;

        IF @TemplateStatus IS NULL
            THROW 60012, 'sp_CreateVenueTemplateVersion: VenueTemplate khong ton tai.', 1;

        IF @TemplateStatus <> 'Active'
            THROW 60013, 'sp_CreateVenueTemplateVersion: Khong tao version moi cho VenueTemplate da Archived.', 1;

        IF EXISTS (SELECT 1 FROM VenueTemplateVersion WHERE VenueTemplateID = @VenueTemplateID AND VersionStatus = 'Draft')
            THROW 60014, 'sp_CreateVenueTemplateVersion: Template dang co mot Draft mo. Publish hoac huy Draft hien tai truoc khi tao Draft moi.', 1;

        IF @CopyFromVersionID IS NOT NULL AND NOT EXISTS (
            SELECT 1 FROM VenueTemplateVersion WHERE VenueTemplateVersionID = @CopyFromVersionID AND VenueTemplateID = @VenueTemplateID
        )
            THROW 60015, 'sp_CreateVenueTemplateVersion: CopyFromVersionID khong thuoc cung VenueTemplate.', 1;

        DECLARE @NextVersionNumber INT =
            ISNULL((SELECT MAX(VersionNumber) FROM VenueTemplateVersion WHERE VenueTemplateID = @VenueTemplateID), 0) + 1;

        INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
        VALUES (@VenueTemplateID, @NextVersionNumber, 'Draft', @ActorUserID);

        SET @NewVenueTemplateVersionID = SCOPE_IDENTITY();

        IF @CopyFromVersionID IS NOT NULL
        BEGIN
            DECLARE @FloorMap TABLE (OldID INT PRIMARY KEY, NewID INT NOT NULL);
            DECLARE @SectionMap TABLE (OldID INT PRIMARY KEY, NewID INT NOT NULL);

            MERGE INTO TemplateFloor AS tgt
            USING (
                SELECT TemplateFloorID AS OldID, FloorKey, FloorName, FloorOrder, CanvasWidth, CanvasHeight
                FROM TemplateFloor WHERE VenueTemplateVersionID = @CopyFromVersionID
            ) AS src
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (VenueTemplateVersionID, FloorKey, FloorName, FloorOrder, CanvasWidth, CanvasHeight)
                VALUES (@NewVenueTemplateVersionID, src.FloorKey, src.FloorName, src.FloorOrder, src.CanvasWidth, src.CanvasHeight)
            OUTPUT src.OldID, inserted.TemplateFloorID INTO @FloorMap(OldID, NewID);

            MERGE INTO TemplateObject AS tgt
            USING (
                SELECT o.TemplateObjectID AS OldID, fm.NewID AS NewFloorID, o.ObjectType, o.Label, o.GeometryJson, o.ZIndex
                FROM TemplateObject o
                JOIN @FloorMap fm ON fm.OldID = o.TemplateFloorID
            ) AS src
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (TemplateFloorID, ObjectType, Label, GeometryJson, ZIndex)
                VALUES (src.NewFloorID, src.ObjectType, src.Label, src.GeometryJson, src.ZIndex);

            MERGE INTO TemplateSection AS tgt
            USING (
                SELECT s.TemplateSectionID AS OldID, fm.NewID AS NewFloorID, s.SectionKey, s.SectionName, s.GeometryJson
                FROM TemplateSection s
                JOIN @FloorMap fm ON fm.OldID = s.TemplateFloorID
            ) AS src
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (TemplateFloorID, SectionKey, SectionName, GeometryJson)
                VALUES (src.NewFloorID, src.SectionKey, src.SectionName, src.GeometryJson)
            OUTPUT src.OldID, inserted.TemplateSectionID INTO @SectionMap(OldID, NewID);

            MERGE INTO TemplateSeat AS tgt
            USING (
                SELECT sm.NewID AS NewSectionID, t.SeatID, t.SeatKey, t.RowLabel, t.SeatNumber, t.GeometryJson, t.IsAccessible, t.IsCompanion
                FROM TemplateSeat t
                JOIN @SectionMap sm ON sm.OldID = t.TemplateSectionID
            ) AS src
            ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber, GeometryJson, IsAccessible, IsCompanion)
                VALUES (src.NewSectionID, src.SeatID, src.SeatKey, src.RowLabel, src.SeatNumber, src.GeometryJson, src.IsAccessible, src.IsCompanion);
        END

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'VENUE_TEMPLATE_VERSION_CREATED', 'VenueTemplateVersion', CAST(@NewVenueTemplateVersionID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"VenueTemplateID":' + CAST(@VenueTemplateID AS VARCHAR(20)) + ',"VersionNumber":' + CAST(@NextVersionNumber AS VARCHAR(20)) +
                ',"CopyFromVersionID":' + ISNULL(CAST(@CopyFromVersionID AS VARCHAR(20)), 'null') + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
