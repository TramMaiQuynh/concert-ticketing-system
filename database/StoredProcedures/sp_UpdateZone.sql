-- ============================================================
-- sp_UpdateZone (BP2 / FR08, FR59b / BR50e)
-- Cap nhat thong tin Zone va chuyen ZoneStatus Active <-> Retired. CHI Admin.
--
-- Ly do SP nay ton tai: sp_AddEventSeats DOC ZoneStatus de tu choi ghe thuoc Zone
-- da Retired (THROW 58219), nhung truoc day khong co duong ghi nao dat duoc
-- 'Retired' - lop kiem tra do khong bao gio kich hoat duoc (§24.4).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateZone
(
    @ActorUserID     INT,
    @ZoneID          INT,
    @ZoneName        NVARCHAR(255) = NULL,
    @ZoneDescription NVARCHAR(500) = NULL,
    @ZoneStatus      VARCHAR(32)   = NULL,
    -- ── Hinh hoc (FR11a) — NULL = giu nguyen ────────────────────────────────
    @ZoneType        VARCHAR(24)   = NULL,
    @ZoneLevel       INT           = NULL,
    @ZoneX           INT           = NULL,
    @ZoneY           INT           = NULL,
    @ZoneWidth       INT           = NULL,
    @ZoneHeight      INT           = NULL,
    @ZoneRotation    DECIMAL(6,2)  = NULL,
    @ZoneCapacity    INT           = NULL,
    @ClearGeometry   BIT           = 0
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura
                       JOIN   Role r ON r.RoleID = ura.RoleID
                       JOIN   UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE  ura.UserID = @ActorUserID
                         AND  r.RoleName = 'Admin'
                         AND  ura.AssignmentStatus = 'Active'
                         AND  uaAdm.AccountStatus  = 'Active')
            THROW 59411, 'sp_UpdateZone: Chi Admin duoc cap nhat Zone.', 1;

        DECLARE @OldStatus VARCHAR(32);
        SELECT @OldStatus = ZoneStatus FROM Zone WITH (UPDLOCK) WHERE ZoneID = @ZoneID;

        IF @OldStatus IS NULL
            THROW 59412, 'sp_UpdateZone: Zone khong ton tai.', 1;

        DECLARE @TargetVenueID INT,
                @OldLevel INT,
                @OldX INT, @OldY INT, @OldWidth INT, @OldHeight INT,
                @OldRotation DECIMAL(6,2);
        SELECT @TargetVenueID = VenueID,
               @OldLevel = ZoneLevel,
               @OldX = ZoneX, @OldY = ZoneY, @OldWidth = ZoneWidth,
               @OldHeight = ZoneHeight, @OldRotation = ZoneRotation
        FROM Zone
        WHERE ZoneID = @ZoneID;

        -- ── Kiem tra hinh hoc khu ──────────────────────────────────────────
        IF @ZoneType IS NOT NULL AND @ZoneType <> 'Seated'
            THROW 59831, 'sp_UpdateZone: He thong hien chi ho tro khu co ghe danh so (Seated).', 1;

        IF @ZoneLevel IS NOT NULL AND @ZoneLevel <= 0
            THROW 59833, 'sp_UpdateZone: Tang/khan dai phai la so nguyen duong.', 1;

        -- NULL cua PATCH thong thuong co nghia "giu nguyen". Trinh bien tap so do
        -- dung ClearGeometry de bo dat vi tri co chu dich; khong co co nay thi
        -- xoa cac o nhap se bi COALESCE giu lai toa do cu va tao loi im lang.
        IF @ClearGeometry = 1
           AND (@ZoneX IS NOT NULL OR @ZoneY IS NOT NULL OR @ZoneWidth IS NOT NULL
                OR @ZoneHeight IS NOT NULL OR @ZoneRotation IS NOT NULL)
            THROW 59812, 'sp_UpdateZone: ClearGeometry khong duoc di kem toa do hoac goc xoay.', 1;

        -- Khong duoc lam an khu da co ve trong mot dia diem dang dung SVG. Nhu
        -- vay EventSeat van ton tai trong kho nhung khach khong con thay de chon.
        IF @ClearGeometry = 1
           AND EXISTS (
               SELECT 1
               FROM EventSeat es
               JOIN Seat s    ON s.SeatID = es.SeatID
               JOIN Concert c ON c.ConcertID = es.ConcertID
               JOIN Venue v   ON v.VenueID = c.VenueID
               WHERE s.ZoneID = @ZoneID
                 AND v.MapWidth IS NOT NULL
                 AND c.ConcertStatus IN ('Draft', 'Published', 'OnSale', 'SaleClosed')
           )
            THROW 59830, 'sp_UpdateZone: Khong the bo vi tri Zone dang co ghe trong kho ve cua Concert chua ket thuc.', 1;

        -- Hop bao: hoac khong khai bao gi, hoac du bon gia tri. Mot khu chi biet
        -- X ma khong biet Width thi khong ve duoc, va de lot vao co so du lieu se
        -- sinh ra so do vo.
        IF (@ZoneX IS NOT NULL OR @ZoneY IS NOT NULL OR @ZoneWidth IS NOT NULL OR @ZoneHeight IS NOT NULL)
           AND (@ZoneX IS NULL OR @ZoneY IS NULL OR @ZoneWidth IS NULL OR @ZoneHeight IS NULL)
            THROW 59812, 'sp_UpdateZone: Vi tri khu phai co du X, Y, Width, Height.', 1;

        DECLARE @FinalX INT = CASE WHEN @ClearGeometry = 1 THEN NULL ELSE COALESCE(@ZoneX, @OldX) END,
                @FinalY INT = CASE WHEN @ClearGeometry = 1 THEN NULL ELSE COALESCE(@ZoneY, @OldY) END,
                @FinalWidth INT = CASE WHEN @ClearGeometry = 1 THEN NULL ELSE COALESCE(@ZoneWidth, @OldWidth) END,
                @FinalHeight INT = CASE WHEN @ClearGeometry = 1 THEN NULL ELSE COALESCE(@ZoneHeight, @OldHeight) END,
                @FinalRotation DECIMAL(6,2) = CASE WHEN @ClearGeometry = 1 THEN NULL ELSE COALESCE(@ZoneRotation, @OldRotation) END,
                @FinalLevel INT = COALESCE(@ZoneLevel, @OldLevel);

        IF @FinalRotation IS NOT NULL AND (@FinalRotation <= -360 OR @FinalRotation >= 360)
            THROW 59816, 'sp_UpdateZone: Goc xoay phai trong khoang -360 den 360 do.', 1;

        IF @FinalX IS NOT NULL
        BEGIN
            IF @FinalWidth <= 0 OR @FinalHeight <= 0
                THROW 59813, 'sp_UpdateZone: Kich thuoc khu phai lon hon 0.', 1;

            -- WITH (UPDLOCK): tranh chap dong thoi voi sp_ConfigureVenueMap (chinh no
            -- cung khoa dong Venue nay bang UPDLOCK khi doc). Neu doc thuong (khong
            -- khoa), mot lenh thu nho mat phang dang chay song song co the chua kip
            -- COMMIT gia tri moi luc dong nay doc, nen khu duoc di chuyen hop le voi
            -- mat phang CU roi mat phang bi thu nho ngay sau do - khu troi ra ngoai
            -- bien ma khong bi bat o dau ca. Da chung minh bang thuc nghiem: dong bo
            -- hoa qua sys.dm_exec_requests, tao ra vi pham that. Voi UPDLOCK, hai giao
            -- dich cung tranh chap DUNG DONG Venue nay se xep hang tuan tu - ben nao
            -- chay xong truoc thi ben sau doc duoc gia tri MOI NHAT, khong con doc
            -- duoc gia tri cu da lac hau.
            DECLARE @VW INT, @VH INT, @StageX INT, @StageY INT, @StageWidth INT, @StageHeight INT;
            SELECT @VW = MapWidth, @VH = MapHeight,
                   @StageX = StageX, @StageY = StageY,
                   @StageWidth = StageWidth, @StageHeight = StageHeight
            FROM Venue WITH (UPDLOCK)
            WHERE VenueID = @TargetVenueID;

            IF @VW IS NULL OR @VH IS NULL
                THROW 59814,
                      'sp_UpdateZone: Chua cau hinh so do dia diem. Goi sp_ConfigureVenueMap truoc khi dat vi tri khu.', 1;

            DECLARE @Radians FLOAT = CONVERT(FLOAT, ISNULL(@FinalRotation, 0)) * PI() / 180.0,
                    @HalfW FLOAT = CONVERT(FLOAT, @FinalWidth) / 2.0,
                    @HalfH FLOAT = CONVERT(FLOAT, @FinalHeight) / 2.0,
                    @CenterX FLOAT = CONVERT(FLOAT, @FinalX) + CONVERT(FLOAT, @FinalWidth) / 2.0,
                    @CenterY FLOAT = CONVERT(FLOAT, @FinalY) + CONVERT(FLOAT, @FinalHeight) / 2.0;
            DECLARE @Cos FLOAT = COS(@Radians),
                    @Sin FLOAT = SIN(@Radians),
                    @ExtentX FLOAT = ABS(@HalfW * COS(@Radians)) + ABS(@HalfH * SIN(@Radians)),
                    @ExtentY FLOAT = ABS(@HalfW * SIN(@Radians)) + ABS(@HalfH * COS(@Radians));

            IF @CenterX - @ExtentX < 0 OR @CenterY - @ExtentY < 0
               OR @CenterX + @ExtentX > @VW OR @CenterY + @ExtentY > @VH
                THROW 59815, 'sp_UpdateZone: Khu nam ngoai mat phang cua dia diem.', 1;

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
                    THROW 59820, 'sp_UpdateZone: Khu khong duoc chong len san khau.', 1;
            END

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
                  AND otherZone.ZoneID <> @ZoneID
                  AND otherZone.ZoneStatus = 'Active'
                  AND ISNULL(otherZone.ZoneLevel, 1) = ISNULL(@FinalLevel, 1)
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
                THROW 59832, 'sp_UpdateZone: Khu cung tang khong duoc chong len nhau.', 1;
        END

        -- Suc chua cua khu co ghe la so Seat dang hoat dong; khong nhap mot
        -- gia tri rieng de tranh lech giua suc chua va so ghe co the ban.
        IF @ZoneCapacity IS NOT NULL
            THROW 59818, 'sp_UpdateZone: Suc chua Zone khong ap dung cho khu co ghe; so ghe quyet dinh suc chua.', 1;

        IF @ZoneStatus IS NOT NULL AND @ZoneStatus NOT IN ('Active', 'Retired')
            THROW 59413, 'sp_UpdateZone: ZoneStatus phai la Active hoac Retired.', 1;

        -- Khong duoc thao do mot Zone ma ghe cua no dang nam trong kho ve cua
        -- Concert chua dien xong - ve da ban se tro toi khu vuc khong con ton tai.
        IF @ZoneStatus = 'Retired' AND @OldStatus = 'Active'
           AND EXISTS (SELECT 1
                       FROM   EventSeat es
                       JOIN   Seat s    ON s.SeatID    = es.SeatID
                       JOIN   Concert c ON c.ConcertID = es.ConcertID
                       WHERE  s.ZoneID = @ZoneID
                         AND  c.ConcertStatus IN ('Draft', 'Published', 'OnSale', 'SaleClosed'))
            THROW 59415, 'sp_UpdateZone: Khong the Retire Zone dang co ghe trong kho ve cua Concert chua ket thuc.', 1;

        UPDATE Zone
        SET    ZoneName        = COALESCE(@ZoneName, ZoneName),
               ZoneDescription = COALESCE(@ZoneDescription, ZoneDescription),
               ZoneStatus      = COALESCE(@ZoneStatus, ZoneStatus),
               ZoneType        = COALESCE(@ZoneType, ZoneType),
               ZoneLevel       = @FinalLevel,
               ZoneX           = @FinalX,
               ZoneY           = @FinalY,
               ZoneWidth       = @FinalWidth,
               ZoneHeight      = @FinalHeight,
               ZoneRotation    = @FinalRotation,
               ZoneCapacity    = NULL
        WHERE  ZoneID = @ZoneID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'ZONE_UPDATED', 'Zone', CAST(@ZoneID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"ZoneStatus":"' + @OldStatus + '"}',
                '{"ZoneStatus":"' + ISNULL(@ZoneStatus, @OldStatus) + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
