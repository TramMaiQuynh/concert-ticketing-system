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
    @StageHeight INT = NULL
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

        -- Gia tri sau khi hop nhat: NULL nghia la giu nguyen.
        DECLARE @W  INT = COALESCE(@MapWidth,    @CurW),
                @H  INT = COALESCE(@MapHeight,   @CurH),
                @SX INT = COALESCE(@StageX,      @CurSX),
                @SY INT = COALESCE(@StageY,      @CurSY),
                @SW INT = COALESCE(@StageWidth,  @CurSW),
                @SH INT = COALESCE(@StageHeight, @CurSH);

        IF (@W IS NOT NULL AND @W <= 0) OR (@H IS NOT NULL AND @H <= 0)
            THROW 59803, 'sp_ConfigureVenueMap: Kich thuoc mat phang phai lon hon 0.', 1;

        -- Mat phang moi khong duoc nho hon vung ma cac khu DA dat dang chiem.
        -- Thieu kiem tra nay thi thu nho so do se day mot so khu ra ngoai khung
        -- va chung bien mat khoi giao dien ma khong bao gi.
        IF @W IS NOT NULL AND @H IS NOT NULL
           AND EXISTS (SELECT 1 FROM Zone
                       WHERE  VenueID = @VenueID
                         AND  ZoneX IS NOT NULL
                         AND  (ZoneX + ZoneWidth > @W OR ZoneY + ZoneHeight > @H))
            THROW 59804,
                  'sp_ConfigureVenueMap: Mat phang moi nho hon vung cac khu dang chiem. Dat lai vi tri cac khu truoc.', 1;

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
