-- ============================================================
-- sp_CreateZone (BP2 / FR08)
-- Tao Zone thuoc Venue. Chi Admin.
-- UNIQUE(VenueID, ZoneCode) dam bao khong trung ma Zone.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateZone
(
    @ActorUserID    INT,
    @VenueID        INT,
    @ZoneCode       VARCHAR(64),
    @ZoneName       NVARCHAR(255),
    -- ── Hinh hoc (FR11a) — tat ca tuy chon ──────────────────────────────────
    -- Phien ban nay chi ho tro khu co ghe danh so (reserved seating).
    @ZoneType       VARCHAR(24)   = 'Seated',
    @ZoneLevel      INT           = NULL,   -- tang/khan dai, 1 = tang tret
    @ZoneX          INT           = NULL,
    @ZoneY          INT           = NULL,
    @ZoneWidth      INT           = NULL,
    @ZoneHeight     INT           = NULL,
    @ZoneRotation   DECIMAL(6,2)  = NULL,   -- do, de xoay khu huong ve san khau
    @ZoneCapacity   INT           = NULL,
    @NewZoneID      INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 58111, 'sp_CreateZone: Chi Admin duoc tao Zone.', 1;

        IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID = @VenueID)
            THROW 58112, 'sp_CreateZone: Venue khong ton tai.', 1;

        IF ISNULL(@ZoneCode, '') = ''
            THROW 58113, 'sp_CreateZone: ZoneCode khong duoc de trong.', 1;

        DECLARE @TargetVenueID INT = @VenueID;

        -- ── Kiem tra hinh hoc khu ──────────────────────────────────────────
        IF @ZoneType IS NOT NULL AND @ZoneType <> 'Seated'
            THROW 59831, 'sp_CreateZone: He thong hien chi ho tro khu co ghe danh so (Seated).', 1;

        IF @ZoneLevel IS NOT NULL AND @ZoneLevel <= 0
            THROW 59833, 'sp_CreateZone: Tang/khan dai phai la so nguyen duong.', 1;

        -- Hop bao: hoac khong khai bao gi, hoac du bon gia tri. Mot khu chi biet
        -- X ma khong biet Width thi khong ve duoc, va de lot vao co so du lieu se
        -- sinh ra so do vo.
        IF (@ZoneX IS NOT NULL OR @ZoneY IS NOT NULL OR @ZoneWidth IS NOT NULL OR @ZoneHeight IS NOT NULL)
           AND (@ZoneX IS NULL OR @ZoneY IS NULL OR @ZoneWidth IS NULL OR @ZoneHeight IS NULL)
            THROW 59812, 'sp_CreateZone: Vi tri khu phai co du X, Y, Width, Height.', 1;

        IF @ZoneRotation IS NOT NULL AND (@ZoneRotation <= -360 OR @ZoneRotation >= 360)
            THROW 59816, 'sp_CreateZone: Goc xoay phai trong khoang -360 den 360 do.', 1;

        IF @ZoneX IS NOT NULL
        BEGIN
            IF @ZoneWidth <= 0 OR @ZoneHeight <= 0
                THROW 59813, 'sp_CreateZone: Kich thuoc khu phai lon hon 0.', 1;

            -- WITH (UPDLOCK): tranh chap dong thoi voi sp_ConfigureVenueMap (chinh no
            -- cung khoa dong Venue nay bang UPDLOCK khi doc). Neu doc thuong (khong
            -- khoa), mot lenh thu nho mat phang dang chay song song co the chua kip
            -- COMMIT gia tri moi luc dong nay doc, nen khu duoc tao hop le voi mat
            -- phang CU roi mat phang bi thu nho ngay sau do - khu troi ra ngoai bien
            -- ma khong bi bat o dau ca. Da chung minh bang thuc nghiem: dong bo hoa
            -- qua sys.dm_exec_requests, lap lai 3/3 lan deu tao ra vi pham that. Voi
            -- UPDLOCK, hai giao dich cung tranh chap DUNG DONG Venue nay se xep hang
            -- tuan tu - ben nao chay xong truoc thi ben sau doc duoc gia tri MOI NHAT,
            -- khong con doc duoc gia tri cu da lac hau.
            DECLARE @VW INT, @VH INT, @StageX INT, @StageY INT, @StageWidth INT, @StageHeight INT;
            SELECT @VW = MapWidth, @VH = MapHeight,
                   @StageX = StageX, @StageY = StageY,
                   @StageWidth = StageWidth, @StageHeight = StageHeight
            FROM Venue WITH (UPDLOCK)
            WHERE VenueID = @TargetVenueID;

            IF @VW IS NULL OR @VH IS NULL
                THROW 59814,
                      'sp_CreateZone: Chua cau hinh so do dia diem. Goi sp_ConfigureVenueMap truoc khi dat vi tri khu.', 1;

            -- Kiem tra hinh CHU NHAT DA XOAY, khong chi hop bao truoc khi xoay.
            -- Cach cu chi kiem tra ZoneX+Width/ZoneY+Height, nen khu xoay 45 do
            -- o sat bien van qua duoc va bi cat mat tren SVG. Bao quet cua hinh
            -- xoay tinh tu nua chieu rong/cao va sin/cos cua goc xoay.
            DECLARE @Radians FLOAT = CONVERT(FLOAT, ISNULL(@ZoneRotation, 0)) * PI() / 180.0,
                    @HalfW FLOAT = CONVERT(FLOAT, @ZoneWidth) / 2.0,
                    @HalfH FLOAT = CONVERT(FLOAT, @ZoneHeight) / 2.0,
                    @CenterX FLOAT = CONVERT(FLOAT, @ZoneX) + CONVERT(FLOAT, @ZoneWidth) / 2.0,
                    @CenterY FLOAT = CONVERT(FLOAT, @ZoneY) + CONVERT(FLOAT, @ZoneHeight) / 2.0;
            DECLARE @Cos FLOAT = COS(@Radians),
                    @Sin FLOAT = SIN(@Radians),
                    @ExtentX FLOAT = ABS(@HalfW * COS(@Radians)) + ABS(@HalfH * SIN(@Radians)),
                    @ExtentY FLOAT = ABS(@HalfW * SIN(@Radians)) + ABS(@HalfH * COS(@Radians));

            IF @CenterX - @ExtentX < 0 OR @CenterY - @ExtentY < 0
               OR @CenterX + @ExtentX > @VW OR @CenterY + @ExtentY > @VH
                THROW 59815, 'sp_CreateZone: Khu nam ngoai mat phang cua dia diem.', 1;

            -- Khong de khu ghe de len san khau. Kiem tra dung hinh chu nhat da
            -- xoay bang Separating Axis Theorem, khong dung AABB de tranh tu choi
            -- sai cac khu nghieng chi cham vao goc san khau.
            IF @StageX IS NOT NULL
            BEGIN
                DECLARE @StageHalfW FLOAT = CONVERT(FLOAT, @StageWidth) / 2.0,
                        @StageHalfH FLOAT = CONVERT(FLOAT, @StageHeight) / 2.0,
                        @DeltaX FLOAT = @CenterX - (CONVERT(FLOAT, @StageX) + CONVERT(FLOAT, @StageWidth) / 2.0),
                        @DeltaY FLOAT = @CenterY - (CONVERT(FLOAT, @StageY) + CONVERT(FLOAT, @StageHeight) / 2.0);

                IF ABS(@DeltaX * @Cos + @DeltaY * @Sin) < @HalfW + @StageHalfW * ABS(@Cos) + @StageHalfH * ABS(@Sin)
                   AND ABS(-@DeltaX * @Sin + @DeltaY * @Cos) < @HalfH + @StageHalfW * ABS(@Sin) + @StageHalfH * ABS(@Cos)
                   AND ABS(@DeltaX) < @StageHalfW + @HalfW * ABS(@Cos) + @HalfH * ABS(@Sin)
                   AND ABS(@DeltaY) < @StageHalfH + @HalfW * ABS(@Sin) + @HalfH * ABS(@Cos)
                    THROW 59820, 'sp_CreateZone: Khu khong duoc chong len san khau.', 1;
            END

            -- Cac khu cung tang la cac vung ban ve phan biet, nen khong duoc de
            -- chong len nhau. Tang khac co the dung cung hinh chieu (ban cong
            -- nam tren khan dai tang tret), vi renderer cho nguoi mua chon tung
            -- tang. Kiem tra SAT ben duoi dung cho hai hinh chu nhat da xoay;
            -- cham canh van hop le vi tat ca phep so sanh deu dung <, khong dung <=.
            -- Venue dang duoc UPDLOCK o tren nen tat ca lenh sua hinh hoc dung SP
            -- nay se xep hang; khong can khoa them Zone va khong tao deadlock voi
            -- mot giao dich dang doi den khoa Venue.
            IF EXISTS (
                SELECT 1
                FROM Zone AS otherZone
                CROSS APPLY (
                    SELECT CONVERT(FLOAT, ISNULL(otherZone.ZoneRotation, 0)) * PI() / 180.0 AS OtherRadians,
                           CONVERT(FLOAT, otherZone.ZoneX) + CONVERT(FLOAT, otherZone.ZoneWidth) / 2.0 AS OtherCenterX,
                           CONVERT(FLOAT, otherZone.ZoneY) + CONVERT(FLOAT, otherZone.ZoneHeight) / 2.0 AS OtherCenterY,
                           CONVERT(FLOAT, otherZone.ZoneWidth) / 2.0 AS OtherHalfW,
                           CONVERT(FLOAT, otherZone.ZoneHeight) / 2.0 AS OtherHalfH
                ) AS otherGeometry
                CROSS APPLY (
                    SELECT COS(otherGeometry.OtherRadians) AS OtherCos,
                           SIN(otherGeometry.OtherRadians) AS OtherSin
                ) AS otherAxis
                CROSS APPLY (
                    SELECT @CenterX - otherGeometry.OtherCenterX AS DeltaX,
                           @CenterY - otherGeometry.OtherCenterY AS DeltaY
                ) AS delta
                WHERE otherZone.VenueID = @TargetVenueID
                  AND otherZone.ZoneStatus = 'Active'
                  AND ISNULL(otherZone.ZoneLevel, 1) = ISNULL(@ZoneLevel, 1)
                  AND otherZone.ZoneX IS NOT NULL
                  AND ABS(delta.DeltaX * @Cos + delta.DeltaY * @Sin)
                        < @HalfW + otherGeometry.OtherHalfW * ABS(@Cos * otherAxis.OtherCos + @Sin * otherAxis.OtherSin)
                                   + otherGeometry.OtherHalfH * ABS(-@Cos * otherAxis.OtherSin + @Sin * otherAxis.OtherCos)
                  AND ABS(-delta.DeltaX * @Sin + delta.DeltaY * @Cos)
                        < @HalfH + otherGeometry.OtherHalfW * ABS(-@Sin * otherAxis.OtherCos + @Cos * otherAxis.OtherSin)
                                   + otherGeometry.OtherHalfH * ABS(@Sin * otherAxis.OtherSin + @Cos * otherAxis.OtherCos)
                  AND ABS(delta.DeltaX * otherAxis.OtherCos + delta.DeltaY * otherAxis.OtherSin)
                        < otherGeometry.OtherHalfW + @HalfW * ABS(@Cos * otherAxis.OtherCos + @Sin * otherAxis.OtherSin)
                                                   + @HalfH * ABS(-@Sin * otherAxis.OtherCos + @Cos * otherAxis.OtherSin)
                  AND ABS(-delta.DeltaX * otherAxis.OtherSin + delta.DeltaY * otherAxis.OtherCos)
                        < otherGeometry.OtherHalfH + @HalfW * ABS(-@Cos * otherAxis.OtherSin + @Sin * otherAxis.OtherCos)
                                                   + @HalfH * ABS(@Sin * otherAxis.OtherSin + @Cos * otherAxis.OtherCos)
            )
                THROW 59832, 'sp_CreateZone: Khu cung tang khong duoc chong len nhau.', 1;
        END

        -- Suc chua cua khu co ghe la so Seat dang hoat dong; khong nhap mot
        -- gia tri rieng de tranh lech giua suc chua va so ghe co the ban.
        IF @ZoneCapacity IS NOT NULL
            THROW 59818, 'sp_CreateZone: Suc chua Zone khong ap dung cho khu co ghe; so ghe quyet dinh suc chua.', 1;

        INSERT INTO Zone (VenueID, ZoneCode, ZoneName, ZoneType, ZoneLevel,
                          ZoneX, ZoneY, ZoneWidth, ZoneHeight, ZoneRotation, ZoneCapacity)
        VALUES (@VenueID, @ZoneCode, @ZoneName, ISNULL(@ZoneType, 'Seated'), @ZoneLevel,
                @ZoneX, @ZoneY, @ZoneWidth, @ZoneHeight, @ZoneRotation, @ZoneCapacity);

        SET @NewZoneID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'ZONE_CREATED', 'Zone', CAST(@NewZoneID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"ZoneCode":"' + STRING_ESCAPE(@ZoneCode, 'json') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
