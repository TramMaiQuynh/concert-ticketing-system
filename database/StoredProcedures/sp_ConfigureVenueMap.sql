-- ============================================================
-- sp_ConfigureVenueMap (FR11a)
-- Khai bao MAT PHANG TOA DO va VI TRI SAN KHAU cua mot Venue. CHI Admin.
--
-- Vi sao tach thanh SP rieng thay vi nhoi them tham so vao sp_UpdateVenue:
-- doi ten hay dia chi la mot viec, dinh nghia hinh hoc so do la mot viec khac
-- han — no co bo kiem tra rieng (san khau phai nam trong mat phang, mat phang
-- khong duoc thu nho hon cac khu da dat) va duoc goi voi tan suat khac han.
-- Cung mau voi sp_ConfigureQueue / sp_ConfigureWaitlist da co san.
--
-- DON VI: so nguyen TRU TUONG, khong phai met hay pixel. Giao dien co gian toan
-- bo so do vao khung hinh dang co, nen mot so do dung duoc tren ca dien thoai
-- lan man hinh lon ma khong can du lieu do dac thuc dia.
--
-- Tham so NULL = giu nguyen gia tri hien tai.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureVenueMap
(
    @ActorUserID INT,
    @VenueID     INT,
    @MapWidth    INT = NULL,
    @MapHeight   INT = NULL,
    @StageX      INT = NULL,
    @StageY      INT = NULL,
    @StageWidth  INT = NULL,
    @StageHeight INT = NULL,
    @ClearStage  BIT = 0,
    @ClearMap    BIT = 0
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
            THROW 59801, 'sp_ConfigureVenueMap: Chi Admin duoc cau hinh so do dia diem.', 1;

        DECLARE @CurW INT, @CurH INT, @CurSX INT, @CurSY INT, @CurSW INT, @CurSH INT;
        SELECT @CurW = MapWidth, @CurH = MapHeight,
               @CurSX = StageX, @CurSY = StageY, @CurSW = StageWidth, @CurSH = StageHeight
        FROM   Venue WITH (UPDLOCK)
        WHERE  VenueID = @VenueID;

        IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID = @VenueID)
            THROW 59802, 'sp_ConfigureVenueMap: Venue khong ton tai.', 1;

        -- Gia tri sau khi hop nhat: NULL nghia la giu nguyen. ClearStage la
        -- thao tac rieng de bo tron ven ca hop san khau, khong de lai du lieu
        -- nua cu nua moi va cung khong bat UI phai dung gia tri sentinel.
        IF @ClearMap = 1
           AND (@MapWidth IS NOT NULL OR @MapHeight IS NOT NULL
                OR @StageX IS NOT NULL OR @StageY IS NOT NULL
                OR @StageWidth IS NOT NULL OR @StageHeight IS NOT NULL
                OR @ClearStage = 1)
            THROW 59805, 'sp_ConfigureVenueMap: ClearMap khong duoc di kem kich thuoc map hay san khau.', 1;

        IF @ClearStage = 1
           AND (@StageX IS NOT NULL OR @StageY IS NOT NULL OR @StageWidth IS NOT NULL OR @StageHeight IS NOT NULL)
            THROW 59805, 'sp_ConfigureVenueMap: ClearStage khong duoc di kem toa do san khau.', 1;

        DECLARE @W  INT = CASE WHEN @ClearMap = 1 THEN NULL ELSE COALESCE(@MapWidth, @CurW) END,
                @H  INT = CASE WHEN @ClearMap = 1 THEN NULL ELSE COALESCE(@MapHeight, @CurH) END,
                @SX INT = CASE WHEN @ClearMap = 1 OR @ClearStage = 1 THEN NULL ELSE COALESCE(@StageX,      @CurSX) END,
                @SY INT = CASE WHEN @ClearMap = 1 OR @ClearStage = 1 THEN NULL ELSE COALESCE(@StageY,      @CurSY) END,
                @SW INT = CASE WHEN @ClearMap = 1 OR @ClearStage = 1 THEN NULL ELSE COALESCE(@StageWidth,  @CurSW) END,
                @SH INT = CASE WHEN @ClearMap = 1 OR @ClearStage = 1 THEN NULL ELSE COALESCE(@StageHeight, @CurSH) END;

        IF (@W IS NULL AND @H IS NOT NULL) OR (@W IS NOT NULL AND @H IS NULL)
            THROW 59803, 'sp_ConfigureVenueMap: Mat phang phai co du ca chieu rong va chieu cao.', 1;

        IF (@W IS NOT NULL AND @W <= 0) OR (@H IS NOT NULL AND @H <= 0)
            THROW 59803, 'sp_ConfigureVenueMap: Kich thuoc mat phang phai lon hon 0.', 1;

        -- Mat phang moi khong duoc nho hon vung ma cac khu DA dat dang chiem.
        -- Thieu kiem tra nay thi thu nho so do se day mot so khu ra ngoai khung
        -- va chung bien mat khoi giao dien ma khong bao gi.
        IF @W IS NOT NULL AND @H IS NOT NULL
           AND EXISTS (
               SELECT 1
               FROM Zone z
               CROSS APPLY (
                   SELECT CONVERT(FLOAT, ISNULL(z.ZoneRotation, 0)) * PI() / 180.0 AS Radians,
                          CONVERT(FLOAT, z.ZoneX) + CONVERT(FLOAT, z.ZoneWidth) / 2.0 AS CenterX,
                          CONVERT(FLOAT, z.ZoneY) + CONVERT(FLOAT, z.ZoneHeight) / 2.0 AS CenterY,
                          CONVERT(FLOAT, z.ZoneWidth) / 2.0 AS HalfW,
                          CONVERT(FLOAT, z.ZoneHeight) / 2.0 AS HalfH
               ) p
               CROSS APPLY (
                   SELECT ABS(p.HalfW * COS(p.Radians)) + ABS(p.HalfH * SIN(p.Radians)) AS ExtentX,
                          ABS(p.HalfW * SIN(p.Radians)) + ABS(p.HalfH * COS(p.Radians)) AS ExtentY
               ) e
               WHERE z.VenueID = @VenueID
                 AND z.ZoneStatus = 'Active'
                 AND z.ZoneX IS NOT NULL
                 AND (p.CenterX - e.ExtentX < 0 OR p.CenterY - e.ExtentY < 0
                      OR p.CenterX + e.ExtentX > @W OR p.CenterY + e.ExtentY > @H)
           )
            THROW 59804,
                  'sp_ConfigureVenueMap: Mat phang moi nho hon vung cac khu dang chiem. Dat lai vi tri cac khu truoc.', 1;

        -- Khong bat/chinh sua renderer SVG khi kho ve dang co ghe thuoc khu chua
        -- dat vi tri. Neu khong, frontend se dung seat map va bo sot toan bo ve
        -- cua khu do thay vi co fallback danh sach.
        IF @W IS NOT NULL AND @H IS NOT NULL
           AND EXISTS (
               SELECT 1
               FROM EventSeat es
               JOIN Seat s    ON s.SeatID = es.SeatID
               JOIN Zone z    ON z.ZoneID = s.ZoneID
               JOIN Concert c ON c.ConcertID = es.ConcertID
               WHERE c.VenueID = @VenueID
                 AND c.ConcertStatus IN ('Draft', 'Published', 'OnSale', 'SaleClosed')
                 AND (z.ZoneX IS NULL OR z.ZoneY IS NULL OR z.ZoneWidth IS NULL OR z.ZoneHeight IS NULL)
           )
            THROW 59830, 'sp_ConfigureVenueMap: Co khu dang co ghe trong kho ve chua dat vi tri tren so do.', 1;

        -- San khau: hoac khong khai bao gi, hoac khai bao du bon gia tri.
        IF (@SX IS NOT NULL OR @SY IS NOT NULL OR @SW IS NOT NULL OR @SH IS NOT NULL)
           AND (@SX IS NULL OR @SY IS NULL OR @SW IS NULL OR @SH IS NULL)
            THROW 59805, 'sp_ConfigureVenueMap: San khau phai co du X, Y, Width, Height.', 1;

        IF @SX IS NOT NULL
        BEGIN
            IF @W IS NULL OR @H IS NULL
                THROW 59806, 'sp_ConfigureVenueMap: Phai khai bao mat phang truoc khi dat san khau.', 1;

            IF @SW <= 0 OR @SH <= 0
                THROW 59803, 'sp_ConfigureVenueMap: Kich thuoc san khau phai lon hon 0.', 1;

            IF @SX < 0 OR @SY < 0 OR @SX + @SW > @W OR @SY + @SH > @H
                THROW 59807, 'sp_ConfigureVenueMap: San khau phai nam tron trong mat phang.', 1;

            -- San khau va khu ghe la hai phan tu vat ly khong the chiem cung mot
            -- dien tich. Dung SAT cho hinh chu nhat Zone da xoay de khong tu choi
            -- sai chi vi hop bao AABB cua no cham vao san khau.
            IF EXISTS (
                SELECT 1
                FROM Zone z
                CROSS APPLY (
                    SELECT CONVERT(FLOAT, ISNULL(z.ZoneRotation, 0)) * PI() / 180.0 AS Radians,
                           CONVERT(FLOAT, z.ZoneX) + CONVERT(FLOAT, z.ZoneWidth) / 2.0 AS CenterX,
                           CONVERT(FLOAT, z.ZoneY) + CONVERT(FLOAT, z.ZoneHeight) / 2.0 AS CenterY,
                           CONVERT(FLOAT, z.ZoneWidth) / 2.0 AS HalfW,
                           CONVERT(FLOAT, z.ZoneHeight) / 2.0 AS HalfH
                ) p
                CROSS APPLY (
                    SELECT COS(p.Radians) AS Cosine, SIN(p.Radians) AS Sine,
                           p.CenterX - (CONVERT(FLOAT, @SX) + CONVERT(FLOAT, @SW) / 2.0) AS DeltaX,
                           p.CenterY - (CONVERT(FLOAT, @SY) + CONVERT(FLOAT, @SH) / 2.0) AS DeltaY,
                           CONVERT(FLOAT, @SW) / 2.0 AS StageHalfW,
                           CONVERT(FLOAT, @SH) / 2.0 AS StageHalfH
                ) q
                WHERE z.VenueID = @VenueID
                  AND z.ZoneStatus = 'Active'
                  AND z.ZoneX IS NOT NULL
                  AND ABS(q.DeltaX * q.Cosine + q.DeltaY * q.Sine) < p.HalfW + q.StageHalfW * ABS(q.Cosine) + q.StageHalfH * ABS(q.Sine)
                  AND ABS(-q.DeltaX * q.Sine + q.DeltaY * q.Cosine) < p.HalfH + q.StageHalfW * ABS(q.Sine) + q.StageHalfH * ABS(q.Cosine)
                  AND ABS(q.DeltaX) < q.StageHalfW + p.HalfW * ABS(q.Cosine) + p.HalfH * ABS(q.Sine)
                  AND ABS(q.DeltaY) < q.StageHalfH + p.HalfW * ABS(q.Sine) + p.HalfH * ABS(q.Cosine)
            )
                THROW 59820, 'sp_ConfigureVenueMap: San khau khong duoc chong len khu ghe.', 1;
        END

        UPDATE Venue
        SET    MapWidth    = @W,
               MapHeight   = @H,
               StageX      = @SX,
               StageY      = @SY,
               StageWidth  = @SW,
               StageHeight = @SH,
               UpdatedTimestamp = SYSDATETIME()
        WHERE  VenueID = @VenueID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'VENUE_MAP_CONFIGURED', 'Venue', CAST(@VenueID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"MapWidth":' + ISNULL(CAST(@CurW AS VARCHAR(12)), 'null')
                + ',"MapHeight":' + ISNULL(CAST(@CurH AS VARCHAR(12)), 'null') + '}',
                '{"MapWidth":' + ISNULL(CAST(@W AS VARCHAR(12)), 'null')
                + ',"MapHeight":' + ISNULL(CAST(@H AS VARCHAR(12)), 'null')
                + ',"StageX":' + ISNULL(CAST(@SX AS VARCHAR(12)), 'null')
                + ',"StageY":' + ISNULL(CAST(@SY AS VARCHAR(12)), 'null') + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
