-- ============================================================
-- sp_ConfigureTemplateSeat (StagePass D.4)
-- Tao moi/cap nhat MOT TemplateSeat trong mot TemplateSection. Chi Admin.
--
-- Thi hanh bat bien "mot SeatID chi xuat hien mot lan trong MOT
-- VenueTemplateVersion" (pham vi la version, khong phai toan bang — cung
-- Seat vat ly co the xuat hien o hai TEMPLATE KHAC NHAU cua cung Venue) —
-- bat bien nay khong bieu dien duoc bang UNIQUE constraint don gian (can
-- JOIN qua Section -> Floor -> Version), da ghi ro trong comment
-- TemplateSeat.sql la se thi hanh o day bang WITH (UPDLOCK, HOLDLOCK), dung
-- khuon sp_CreateSeat dang khoa key-range chong trung SeatCode trong Zone.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureTemplateSeat
(
    @ActorUserID       INT,
    @TemplateSectionID INT,
    @SeatID            INT,
    @SeatKey           VARCHAR(64),
    @RowLabel          NVARCHAR(16) = NULL,
    @SeatNumber        INT = NULL,
    @GeometryJson      NVARCHAR(MAX) = NULL,
    @IsAccessible      BIT = 0,
    @IsCompanion       BIT = 0,
    @TemplateSeatID    INT = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60101, 'sp_ConfigureTemplateSeat: Chi Admin duoc cau hinh TemplateSeat.', 1;

        DECLARE @VersionStatus VARCHAR(32), @VenueTemplateVersionID INT;
        SELECT @VersionStatus = vtv.VersionStatus, @VenueTemplateVersionID = vtv.VenueTemplateVersionID
        FROM TemplateSection s
        JOIN TemplateFloor f ON f.TemplateFloorID = s.TemplateFloorID
        JOIN VenueTemplateVersion vtv ON vtv.VenueTemplateVersionID = f.VenueTemplateVersionID
        WHERE s.TemplateSectionID = @TemplateSectionID;

        IF @VersionStatus IS NULL
            THROW 60102, 'sp_ConfigureTemplateSeat: TemplateSection khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60103, 'sp_ConfigureTemplateSeat: Chi sua duoc Seat cua version dang Draft.', 1;

        IF NOT EXISTS (SELECT 1 FROM Seat WHERE SeatID = @SeatID)
            THROW 60104, 'sp_ConfigureTemplateSeat: SeatID khong ton tai.', 1;

        IF ISNULL(@SeatKey, '') = ''
            THROW 60105, 'sp_ConfigureTemplateSeat: SeatKey khong duoc de trong.', 1;

        IF (@RowLabel IS NULL AND @SeatNumber IS NOT NULL) OR (@RowLabel IS NOT NULL AND @SeatNumber IS NULL)
            THROW 60106, 'sp_ConfigureTemplateSeat: RowLabel va SeatNumber phai cung co hoac cung khong co.', 1;

        -- Khoa key-range: moi dong TemplateSeat CO CUNG SeatID trong CUNG
        -- version nay, qua ca cay Section -> Floor. UPDLOCK, HOLDLOCK giu
        -- khoa den het transaction, chan hai request cung EXEC chen trung
        -- SeatID vao cung version truoc khi ben nao kip COMMIT.
        IF EXISTS (
            SELECT 1
            FROM TemplateSeat ts WITH (UPDLOCK, HOLDLOCK)
            JOIN TemplateSection s2 ON s2.TemplateSectionID = ts.TemplateSectionID
            JOIN TemplateFloor f2 ON f2.TemplateFloorID = s2.TemplateFloorID
            WHERE f2.VenueTemplateVersionID = @VenueTemplateVersionID
              AND ts.SeatID = @SeatID
              AND ts.TemplateSeatID <> ISNULL(@TemplateSeatID, -1)
        )
            THROW 60107, 'sp_ConfigureTemplateSeat: SeatID nay da xuat hien o mot Section khac trong cung VenueTemplateVersion.', 1;

        IF @TemplateSeatID IS NULL OR @TemplateSeatID <= 0
        BEGIN
            IF EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSectionID = @TemplateSectionID AND SeatKey = @SeatKey)
                THROW 60108, 'sp_ConfigureTemplateSeat: SeatKey da ton tai trong Section nay.', 1;

            IF @RowLabel IS NOT NULL AND EXISTS (
                SELECT 1 FROM TemplateSeat WHERE TemplateSectionID = @TemplateSectionID AND RowLabel = @RowLabel AND SeatNumber = @SeatNumber
            )
                THROW 60109, 'sp_ConfigureTemplateSeat: O luoi (RowLabel, SeatNumber) nay da co ghe khac trong Section.', 1;

            INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber, GeometryJson, IsAccessible, IsCompanion)
            VALUES (@TemplateSectionID, @SeatID, @SeatKey, @RowLabel, @SeatNumber, @GeometryJson, ISNULL(@IsAccessible, 0), ISNULL(@IsCompanion, 0));

            SET @TemplateSeatID = SCOPE_IDENTITY();

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_SEAT_CREATED', 'TemplateSeat', CAST(@TemplateSeatID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                    '{"TemplateSectionID":' + CAST(@TemplateSectionID AS VARCHAR(20)) + ',"SeatID":' + CAST(@SeatID AS VARCHAR(20)) + '}');
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSeatID = @TemplateSeatID AND TemplateSectionID = @TemplateSectionID)
                THROW 60110, 'sp_ConfigureTemplateSeat: TemplateSeatID khong thuoc TemplateSection nay.', 1;

            IF EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSectionID = @TemplateSectionID AND SeatKey = @SeatKey AND TemplateSeatID <> @TemplateSeatID)
                THROW 60108, 'sp_ConfigureTemplateSeat: SeatKey da ton tai trong Section nay.', 1;

            IF @RowLabel IS NOT NULL AND EXISTS (
                SELECT 1 FROM TemplateSeat WHERE TemplateSectionID = @TemplateSectionID AND RowLabel = @RowLabel AND SeatNumber = @SeatNumber AND TemplateSeatID <> @TemplateSeatID
            )
                THROW 60109, 'sp_ConfigureTemplateSeat: O luoi (RowLabel, SeatNumber) nay da co ghe khac trong Section.', 1;

            UPDATE TemplateSeat
            SET SeatID = @SeatID, SeatKey = @SeatKey, RowLabel = @RowLabel, SeatNumber = @SeatNumber,
                GeometryJson = @GeometryJson, IsAccessible = ISNULL(@IsAccessible, 0), IsCompanion = ISNULL(@IsCompanion, 0)
            WHERE TemplateSeatID = @TemplateSeatID;

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_SEAT_UPDATED', 'TemplateSeat', CAST(@TemplateSeatID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"SeatID":' + CAST(@SeatID AS VARCHAR(20)) + '}');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
