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
    @ZoneCapacity    INT           = NULL
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

        DECLARE @TargetVenueID INT, @OldType VARCHAR(24);
        SELECT @TargetVenueID = VenueID, @OldType = ZoneType FROM Zone WHERE ZoneID = @ZoneID;

        -- ── Kiem tra hinh hoc khu ──────────────────────────────────────────
        IF @ZoneType IS NOT NULL AND @ZoneType NOT IN ('Seated', 'GeneralAdmission')
            THROW 59811, 'sp_UpdateZone: ZoneType phai la Seated hoac GeneralAdmission.', 1;

        -- Hop bao: hoac khong khai bao gi, hoac du bon gia tri. Mot khu chi biet
        -- X ma khong biet Width thi khong ve duoc, va de lot vao co so du lieu se
        -- sinh ra so do vo.
        IF (@ZoneX IS NOT NULL OR @ZoneY IS NOT NULL OR @ZoneWidth IS NOT NULL OR @ZoneHeight IS NOT NULL)
           AND (@ZoneX IS NULL OR @ZoneY IS NULL OR @ZoneWidth IS NULL OR @ZoneHeight IS NULL)
            THROW 59812, 'sp_UpdateZone: Vi tri khu phai co du X, Y, Width, Height.', 1;

        IF @ZoneX IS NOT NULL
        BEGIN
            IF @ZoneWidth <= 0 OR @ZoneHeight <= 0
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
            DECLARE @VW INT, @VH INT;
            SELECT @VW = MapWidth, @VH = MapHeight FROM Venue WITH (UPDLOCK) WHERE VenueID = @TargetVenueID;

            IF @VW IS NULL OR @VH IS NULL
                THROW 59814,
                      'sp_UpdateZone: Chua cau hinh so do dia diem. Goi sp_ConfigureVenueMap truoc khi dat vi tri khu.', 1;

            IF @ZoneX < 0 OR @ZoneY < 0 OR @ZoneX + @ZoneWidth > @VW OR @ZoneY + @ZoneHeight > @VH
                THROW 59815, 'sp_UpdateZone: Khu nam ngoai mat phang cua dia diem.', 1;
        END

        IF @ZoneRotation IS NOT NULL AND (@ZoneRotation <= -360 OR @ZoneRotation >= 360)
            THROW 59816, 'sp_UpdateZone: Goc xoay phai trong khoang -360 den 360 do.', 1;

        -- Doi mot khu DA co ghe sang khu ve dung se bo roi toan bo ghe do: chung
        -- van ton tai, van bi Ticket lich su tham chieu, nhung khong con thuoc ve
        -- mot khu co ghe nao ca. Chan tu dau thay vi de du lieu roi vao trang thai
        -- khong giai thich duoc.
        IF @ZoneType = 'GeneralAdmission' AND @OldType = 'Seated'
           AND EXISTS (SELECT 1 FROM Seat WHERE ZoneID = @ZoneID AND SeatStatus = 'Active')
            THROW 59819, 'sp_UpdateZone: Khong the chuyen sang khu ve dung khi khu dang co ghe.', 1;

        IF COALESCE(@ZoneType, @OldType) = 'GeneralAdmission'
           AND COALESCE(@ZoneCapacity, (SELECT ZoneCapacity FROM Zone WHERE ZoneID = @ZoneID)) IS NULL
            THROW 59817, 'sp_UpdateZone: Khu ve dung phai khai bao suc chua lon hon 0.', 1;

        IF COALESCE(@ZoneType, @OldType) <> 'GeneralAdmission' AND @ZoneCapacity IS NOT NULL
            THROW 59818, 'sp_UpdateZone: Chi khu ve dung moi co suc chua; khu co ghe thi suc chua do so ghe quyet dinh.', 1;

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
               ZoneLevel       = COALESCE(@ZoneLevel, ZoneLevel),
               ZoneX           = COALESCE(@ZoneX, ZoneX),
               ZoneY           = COALESCE(@ZoneY, ZoneY),
               ZoneWidth       = COALESCE(@ZoneWidth, ZoneWidth),
               ZoneHeight      = COALESCE(@ZoneHeight, ZoneHeight),
               ZoneRotation    = COALESCE(@ZoneRotation, ZoneRotation),
               ZoneCapacity    = CASE WHEN COALESCE(@ZoneType, ZoneType) = 'GeneralAdmission'
                                      THEN COALESCE(@ZoneCapacity, ZoneCapacity)
                                      ELSE NULL END
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
