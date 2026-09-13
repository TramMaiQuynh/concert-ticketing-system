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
    -- 'Seated' co ghe danh so; 'GeneralAdmission' ban theo suc chua, khong co ghe.
    @ZoneType       VARCHAR(24)   = 'Seated',
    @ZoneLevel      INT           = NULL,   -- tang/khan dai, 1 = tang tret
    @ZoneX          INT           = NULL,
    @ZoneY          INT           = NULL,
    @ZoneWidth      INT           = NULL,
    @ZoneHeight     INT           = NULL,
    @ZoneRotation   DECIMAL(6,2)  = NULL,   -- do, de xoay khu huong ve san khau
    @ZoneCapacity   INT           = NULL,   -- CHI cho khu ve dung
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
        IF @ZoneType IS NOT NULL AND @ZoneType NOT IN ('Seated', 'GeneralAdmission')
            THROW 59811, 'sp_CreateZone: ZoneType phai la Seated hoac GeneralAdmission.', 1;

        -- Hop bao: hoac khong khai bao gi, hoac du bon gia tri. Mot khu chi biet
        -- X ma khong biet Width thi khong ve duoc, va de lot vao co so du lieu se
        -- sinh ra so do vo.
        IF (@ZoneX IS NOT NULL OR @ZoneY IS NOT NULL OR @ZoneWidth IS NOT NULL OR @ZoneHeight IS NOT NULL)
           AND (@ZoneX IS NULL OR @ZoneY IS NULL OR @ZoneWidth IS NULL OR @ZoneHeight IS NULL)
            THROW 59812, 'sp_CreateZone: Vi tri khu phai co du X, Y, Width, Height.', 1;

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
            DECLARE @VW INT, @VH INT;
            SELECT @VW = MapWidth, @VH = MapHeight FROM Venue WITH (UPDLOCK) WHERE VenueID = @TargetVenueID;

            IF @VW IS NULL OR @VH IS NULL
                THROW 59814,
                      'sp_CreateZone: Chua cau hinh so do dia diem. Goi sp_ConfigureVenueMap truoc khi dat vi tri khu.', 1;

            IF @ZoneX < 0 OR @ZoneY < 0 OR @ZoneX + @ZoneWidth > @VW OR @ZoneY + @ZoneHeight > @VH
                THROW 59815, 'sp_CreateZone: Khu nam ngoai mat phang cua dia diem.', 1;
        END

        IF @ZoneRotation IS NOT NULL AND (@ZoneRotation <= -360 OR @ZoneRotation >= 360)
            THROW 59816, 'sp_CreateZone: Goc xoay phai trong khoang -360 den 360 do.', 1;

        -- Suc chua thuoc ve khu ve dung, va khu ve dung thi bat buoc phai co:
        -- khong co so nay thi khong ban duoc gi, vi khu do khong co ghe de dem.
        IF @ZoneType = 'GeneralAdmission' AND ISNULL(@ZoneCapacity, 0) <= 0
            THROW 59817, 'sp_CreateZone: Khu ve dung phai khai bao suc chua lon hon 0.', 1;

        IF @ZoneType <> 'GeneralAdmission' AND @ZoneCapacity IS NOT NULL
            THROW 59818, 'sp_CreateZone: Chi khu ve dung moi co suc chua; khu co ghe thi suc chua do so ghe quyet dinh.', 1;

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