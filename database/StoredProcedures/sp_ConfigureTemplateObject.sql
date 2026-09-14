-- ============================================================
-- sp_ConfigureTemplateObject (StagePass D.4)
-- Tao moi/cap nhat mot TemplateObject (san khau, loi di, tuong, cua vao,
-- nha ve sinh, quay bar, nhan chu) trong mot TemplateFloor. Chi Admin.
--
-- Bat buoc GeometryJson hop le CAU TRUC (fn_TemplateGeometryIsStructurallyValid)
-- va LOI (fn_TemplateGeometryIsConvex) — du Object khong tu va cham voi
-- Object khac (chi trang tri/tham chieu, khong ban duoc), no VAN co the la
-- doi tuong duoc so sanh trong fn_TemplateGeometryOverlaps boi
-- sp_ConfigureTemplateSection (khu ghe khong duoc chong len San khau) — SAT
-- chi dung cho hinh loi, nen giu bat bien "moi GeometryJson da luu deu loi"
-- NHAT QUAN cho toan bo lop StagePass thay vi chi ap dung rieng cho Stage.
--
-- Khoa UPDLOCK+HOLDLOCK tren dong TemplateFloor (khong phai VenueTemplateVersion)
-- de tuan tu hoa dung voi sp_ConfigureTemplateSection cung floor — day la hai
-- SP cung doc/ghi tap Object+Section cua MOT floor de kiem tra va cham chong
-- lan, nen phai khoa CHUNG mot tai nguyen, dung tinh than sp_CreateZone/
-- sp_ConfigureVenueMap khoa chung dong Venue.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureTemplateObject
(
    @ActorUserID     INT,
    @TemplateFloorID INT,
    @ObjectType      VARCHAR(32),
    @Label           NVARCHAR(255) = NULL,
    @GeometryJson    NVARCHAR(MAX),
    @ZIndex          INT = 0,
    @TemplateObjectID INT = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 60061, 'sp_ConfigureTemplateObject: Chi Admin duoc cau hinh TemplateObject.', 1;

        DECLARE @VersionStatus VARCHAR(32), @CanvasWidth INT, @CanvasHeight INT;
        SELECT @VersionStatus = vtv.VersionStatus, @CanvasWidth = f.CanvasWidth, @CanvasHeight = f.CanvasHeight
        FROM TemplateFloor f WITH (UPDLOCK, HOLDLOCK)
        JOIN VenueTemplateVersion vtv ON vtv.VenueTemplateVersionID = f.VenueTemplateVersionID
        WHERE f.TemplateFloorID = @TemplateFloorID;

        IF @VersionStatus IS NULL
            THROW 60062, 'sp_ConfigureTemplateObject: TemplateFloor khong ton tai.', 1;

        IF @VersionStatus <> 'Draft'
            THROW 60063, 'sp_ConfigureTemplateObject: Chi sua duoc Object cua version dang Draft.', 1;

        IF @ObjectType NOT IN ('Stage', 'Aisle', 'Wall', 'Entrance', 'Restroom', 'Bar', 'Text', 'Icon')
            THROW 60064, 'sp_ConfigureTemplateObject: ObjectType khong hop le.', 1;

        IF dbo.fn_TemplateGeometryIsStructurallyValid(@GeometryJson) <> 1
            THROW 60065, 'sp_ConfigureTemplateObject: GeometryJson khong dung cau truc (xem quy uoc v1 trong TemplateSection.sql).', 1;

        IF dbo.fn_TemplateGeometryIsConvex(@GeometryJson) <> 1
            THROW 60066, 'sp_ConfigureTemplateObject: Hinh khong loi — StagePass chi ho tro va cham chinh xac cho hinh loi.', 1;

        IF EXISTS (
            SELECT 1 FROM dbo.fn_TemplateGeometryToPoints(@GeometryJson) pt
            WHERE pt.X < 0 OR pt.X > @CanvasWidth OR pt.Y < 0 OR pt.Y > @CanvasHeight
        )
            THROW 60067, 'sp_ConfigureTemplateObject: Object nam ngoai canvas cua Floor.', 1;

        IF @TemplateObjectID IS NULL OR @TemplateObjectID <= 0
        BEGIN
            INSERT INTO TemplateObject (TemplateFloorID, ObjectType, Label, GeometryJson, ZIndex)
            VALUES (@TemplateFloorID, @ObjectType, @Label, @GeometryJson, ISNULL(@ZIndex, 0));

            SET @TemplateObjectID = SCOPE_IDENTITY();

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_OBJECT_CREATED', 'TemplateObject', CAST(@TemplateObjectID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                    '{"TemplateFloorID":' + CAST(@TemplateFloorID AS VARCHAR(20)) + ',"ObjectType":"' + @ObjectType + '"}');
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM TemplateObject WHERE TemplateObjectID = @TemplateObjectID AND TemplateFloorID = @TemplateFloorID)
                THROW 60068, 'sp_ConfigureTemplateObject: TemplateObjectID khong thuoc TemplateFloor nay.', 1;

            UPDATE TemplateObject
            SET ObjectType = @ObjectType, Label = @Label, GeometryJson = @GeometryJson, ZIndex = ISNULL(@ZIndex, 0)
            WHERE TemplateObjectID = @TemplateObjectID;

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TEMPLATE_OBJECT_UPDATED', 'TemplateObject', CAST(@TemplateObjectID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"ObjectType":"' + @ObjectType + '"}');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
