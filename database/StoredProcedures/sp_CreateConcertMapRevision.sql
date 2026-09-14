-- ============================================================
-- sp_CreateConcertMapRevision (StagePass D.5)
-- Chup snapshot BAT BIEN tu mot VenueTemplateVersion (PHAI dang Published)
-- sang mot ConcertMapRevision moi (Draft) cua mot ConcertMap. Sao chep SAU
-- toan bo Floor/Object/Section/Seat sang cac bang ConcertMapRevision*
-- tuong ung, dung ky thuat MERGE...OUTPUT (ON 1=0) da dung trong
-- sp_CreateVenueTemplateVersion (@CopyFromVersionID) de vua INSERT vua lay
-- duoc bang anh xa (OldID, NewID) noi cac tang con.
--
-- Sau khi snapshot, du lieu hinh hoc KHONG con phu thuoc TemplateFloor/
-- Section/Seat nguon — SourceTemplate*ID chi de truy vet (khong FK), dung
-- nguyen tac da ghi trong comment ConcertMapRevisionFloor.sql.
--
-- Admin hoac chinh Organizer cua Concert. Khoa UPDLOCK+HOLDLOCK tren dong
-- ConcertMap de tuan tu hoa cac lan tao revision canh tranh cho CUNG map —
-- can thiet vi UIX_CMR_OneDraftPerMap (moi them) chi bat duoc xung dot SAU
-- khi ca hai giao dich da INSERT, khoa o day giup giao dich thu hai xep
-- hang thay vi cham loi constraint tho.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateConcertMapRevision
(
    @ActorUserID                 INT,
    @ConcertMapID                INT,
    @SourceVenueTemplateVersionID INT,
    @NewConcertMapRevisionID     INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ConcertID INT, @DummyLock INT;
        SELECT @ConcertID = ConcertID, @DummyLock = ConcertMapID
        FROM ConcertMap WITH (UPDLOCK, HOLDLOCK)
        WHERE ConcertMapID = @ConcertMapID;

        IF @ConcertID IS NULL
            THROW 60211, 'sp_CreateConcertMapRevision: ConcertMap khong ton tai.', 1;

        DECLARE @OrganizerUserID INT, @ConcertVenueID INT, @ConcertStatus VARCHAR(32);
        SELECT @OrganizerUserID = OrganizerUserID, @ConcertVenueID = VenueID, @ConcertStatus = ConcertStatus
        FROM Concert WHERE ConcertID = @ConcertID;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 60212, 'sp_CreateConcertMapRevision: Actor khong co quyen (phai la Organizer cua Concert hoac Admin).', 1;

        IF @ConcertVenueID IS NULL
            THROW 60213, 'sp_CreateConcertMapRevision: Concert chua duoc gan Venue.', 1;

        IF @ConcertStatus NOT IN ('Draft', 'Published')
            THROW 60218, 'sp_CreateConcertMapRevision: Khong the sua snapshot map sau khi Concert da mo ban.', 1;

        DECLARE @VersionStatus VARCHAR(32), @TemplateVenueID INT;
        SELECT @VersionStatus = vtv.VersionStatus, @TemplateVenueID = vt.VenueID
        FROM VenueTemplateVersion vtv
        JOIN VenueTemplate vt ON vt.VenueTemplateID = vtv.VenueTemplateID
        WHERE vtv.VenueTemplateVersionID = @SourceVenueTemplateVersionID;

        IF @VersionStatus IS NULL
            THROW 60214, 'sp_CreateConcertMapRevision: SourceVenueTemplateVersionID khong ton tai.', 1;

        IF @VersionStatus <> 'Published'
            THROW 60215, 'sp_CreateConcertMapRevision: Chi duoc snapshot tu VenueTemplateVersion dang Published.', 1;

        IF @TemplateVenueID <> @ConcertVenueID
            THROW 60216, 'sp_CreateConcertMapRevision: VenueTemplate nguon khong thuoc dung Venue cua Concert.', 1;

        IF EXISTS (SELECT 1 FROM ConcertMapRevision WHERE ConcertMapID = @ConcertMapID AND RevisionStatus = 'Draft')
            THROW 60217, 'sp_CreateConcertMapRevision: Map dang co mot Draft mo. Khoa (Lock) hoac huy Draft hien tai truoc khi tao Draft moi.', 1;

        IF EXISTS (SELECT 1 FROM ConcertMapRevision WHERE ConcertMapID = @ConcertMapID AND RevisionStatus = 'Locked')
            THROW 60219, 'sp_CreateConcertMapRevision: Concert da co revision Locked; khong thay the map dang duoc cau hinh/ban ve.', 1;

        DECLARE @NextRevisionNumber INT =
            ISNULL((SELECT MAX(RevisionNumber) FROM ConcertMapRevision WHERE ConcertMapID = @ConcertMapID), 0) + 1;

        INSERT INTO ConcertMapRevision (ConcertMapID, SourceVenueTemplateVersionID, RevisionNumber, RevisionStatus)
        VALUES (@ConcertMapID, @SourceVenueTemplateVersionID, @NextRevisionNumber, 'Draft');

        SET @NewConcertMapRevisionID = SCOPE_IDENTITY();

        DECLARE @FloorMap TABLE (OldID INT PRIMARY KEY, NewID INT NOT NULL);
        DECLARE @SectionMap TABLE (OldID INT PRIMARY KEY, NewID INT NOT NULL);

        MERGE INTO ConcertMapRevisionFloor AS tgt
        USING (
            SELECT TemplateFloorID AS OldID, FloorKey, FloorName, FloorOrder, CanvasWidth, CanvasHeight
            FROM TemplateFloor WHERE VenueTemplateVersionID = @SourceVenueTemplateVersionID
        ) AS src
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (ConcertMapRevisionID, SourceTemplateFloorID, FloorKey, FloorName, FloorOrder, CanvasWidth, CanvasHeight)
            VALUES (@NewConcertMapRevisionID, src.OldID, src.FloorKey, src.FloorName, src.FloorOrder, src.CanvasWidth, src.CanvasHeight)
        OUTPUT src.OldID, inserted.ConcertMapRevisionFloorID INTO @FloorMap(OldID, NewID);

        MERGE INTO ConcertMapRevisionObject AS tgt
        USING (
            SELECT fm.NewID AS NewFloorID, o.ObjectType, o.Label, o.GeometryJson, o.ZIndex
            FROM TemplateObject o
            JOIN @FloorMap fm ON fm.OldID = o.TemplateFloorID
        ) AS src
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (ConcertMapRevisionFloorID, ObjectType, Label, GeometryJson, ZIndex)
            VALUES (src.NewFloorID, src.ObjectType, src.Label, src.GeometryJson, src.ZIndex);

        MERGE INTO ConcertMapRevisionSection AS tgt
        USING (
            SELECT s.TemplateSectionID AS OldID, fm.NewID AS NewFloorID, s.ZoneID, s.SectionKey, s.SectionName, s.GeometryJson
            FROM TemplateSection s
            JOIN @FloorMap fm ON fm.OldID = s.TemplateFloorID
        ) AS src
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (ConcertMapRevisionFloorID, SourceTemplateSectionID, ZoneID, SectionKey, SectionName, GeometryJson)
            VALUES (src.NewFloorID, src.OldID, src.ZoneID, src.SectionKey, src.SectionName, src.GeometryJson)
        OUTPUT src.OldID, inserted.ConcertMapRevisionSectionID INTO @SectionMap(OldID, NewID);

        MERGE INTO ConcertMapRevisionSeat AS tgt
        USING (
            SELECT t.TemplateSeatID AS OldID, sm.NewID AS NewSectionID, t.SeatID, t.SeatKey, t.RowLabel, t.SeatNumber,
                   t.GeometryJson, t.IsAccessible, t.IsCompanion
            FROM TemplateSeat t
            JOIN @SectionMap sm ON sm.OldID = t.TemplateSectionID
        ) AS src
        ON 1 = 0
        WHEN NOT MATCHED THEN
            INSERT (ConcertMapRevisionSectionID, SourceTemplateSeatID, SeatID, SeatKey, RowLabel, SeatNumber, GeometryJson, IsAccessible, IsCompanion)
            VALUES (src.NewSectionID, src.OldID, src.SeatID, src.SeatKey, src.RowLabel, src.SeatNumber, src.GeometryJson, src.IsAccessible, src.IsCompanion);

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'CONCERT_MAP_REVISION_CREATED', 'ConcertMapRevision', CAST(@NewConcertMapRevisionID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"ConcertMapID":' + CAST(@ConcertMapID AS VARCHAR(20)) + ',"SourceVenueTemplateVersionID":' + CAST(@SourceVenueTemplateVersionID AS VARCHAR(20)) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
