CREATE TABLE Venue (
    VenueID INT IDENTITY(1,1) NOT NULL,
    VenueName NVARCHAR(255) NOT NULL,
    Address NVARCHAR(500),
    VenueStatus VARCHAR(32) NOT NULL,
    CreatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),

    -- ── SO DO DIA DIEM: mat phang toa do va diem tieu cu (FR11a) ───────────
    --
    -- MapWidth/MapHeight dinh nghia mot he toa do TRU TUONG cho dia diem nay.
    -- Don vi khong phai met, khong phai pixel — chi la mot luoi de dat cac khu
    -- len. Renderer co gian toan bo so do vao khung hinh dang co, nen so do
    -- hien dung tren mo dien thoai lan man hinh lon ma khong can du lieu do dac.
    --
    -- StageX/Y/Width/Height la DIEM TIEU CU cua so do. Day la thu bien mot dam
    -- hinh chu nhat thanh mot so do co nghia: khong co no thi khong the noi
    -- cho ngoi nao gan san khau hon cho nao, ma do lai chinh la yeu to quyet
    -- dinh gia tri mot chiec ve.
    --
    -- Tat ca NULL duoc. Dia diem chua khai bao so do van hoat dong binh thuong;
    -- giao dien tu rot ve che do liet ke theo khu.
    MapWidth    INT NULL,
    MapHeight   INT NULL,
    StageX      INT NULL,
    StageY      INT NULL,
    StageWidth  INT NULL,
    StageHeight INT NULL,

    CONSTRAINT CHK_Venue_MapSize CHECK (
            (MapWidth  IS NULL OR MapWidth  > 0)
        AND (MapHeight IS NULL OR MapHeight > 0)
    ),
    -- Mat phang la mot cap kich thuoc. Chi co chieu rong hoac chieu cao khong
    -- tao nen mot he toa do, va se khien frontend luon roi ve fallback trong khi
    -- database lai tuong nhu Venue da co map.
    CONSTRAINT CHK_Venue_MapBoxComplete CHECK (
        (MapWidth IS NULL AND MapHeight IS NULL)
     OR (MapWidth IS NOT NULL AND MapHeight IS NOT NULL)
    ),
    CONSTRAINT CHK_Venue_StageSize CHECK (
            (StageWidth  IS NULL OR StageWidth  > 0)
        AND (StageHeight IS NULL OR StageHeight > 0)
    ),
    -- San khau chi co nghia khi da co mat phang chua no.
    CONSTRAINT CHK_Venue_StageNeedsMap CHECK (
        StageX IS NULL OR (MapWidth IS NOT NULL AND MapHeight IS NOT NULL)
    ),
    -- Hop bao san khau phai day du hoac khong co gi: cung mau voi
    -- CHK_Zone_BoxComplete/CHK_Seat_GridComplete o Zone/Seat cho DUNG loai bat bien
    -- (mot hop hinh hoc phai tron ven). Truoc khi co rang buoc nay, tang bang chap
    -- nhan StageX=10 voi StageY/Width/Height=NULL - da kiem chung bang INSERT truc
    -- tiep thanh cong. sp_ConfigureVenueMap van kiem tra dieu nay (loi 59805), nhung
    -- chi tang thu tuc kiem thi bat bien khong duoc dam bao neu co duong ghi nao
    -- khac (vd. thao tac thu cong cua DBA qua app_admin).
    CONSTRAINT CHK_Venue_StageBoxComplete CHECK (
            (StageX IS NULL AND StageY IS NULL AND StageWidth IS NULL AND StageHeight IS NULL)
         OR (StageX IS NOT NULL AND StageY IS NOT NULL AND StageWidth IS NOT NULL AND StageHeight IS NOT NULL)
    ),
    -- San khau phai nam TRON VEN trong mat phang: toa do khong am va khong tran ra
    -- ngoai bien. Truoc khi co rang buoc nay, tang bang chap nhan StageX/Y am va
    -- san khau vuot qua MapWidth/MapHeight - da kiem chung bang INSERT truc tiep
    -- thanh cong. Day la kiem tra CUNG BANG (Map va Stage cung o Venue) nen the
    -- hien duoc tron ven bang CHECK, khac voi Zone-nam-trong-Venue (khac bang,
    -- CHECK cua SQL Server khong tham chieu duoc bang khac - phai dua vao thu tuc,
    -- da khoa dong bo bang WITH (UPDLOCK) trong sp_CreateZone/sp_UpdateZone).
    -- Ghi IS NOT NULL tuong minh cho MapWidth/MapHeight thay vi dua vao ngu nghia
    -- UNKNOWN=PASS cua CHECK constraint (da kiem chung thuc nghiem: neu thieu no,
    -- StageX=5 voi MapWidth=NULL se duoc CHAP NHAN chu khong bi chan) - rang buoc
    -- nay tu no phai dung, khong phu thuoc CHK_Venue_StageNeedsMap o tren.
    CONSTRAINT CHK_Venue_StageWithinMap CHECK (
        StageX IS NULL
        OR (    StageX >= 0 AND StageY >= 0
            AND MapWidth  IS NOT NULL AND StageX + StageWidth  <= MapWidth
            AND MapHeight IS NOT NULL AND StageY + StageHeight <= MapHeight)
    ),
    CONSTRAINT PK_Venue PRIMARY KEY CLUSTERED (VenueID),
    -- Domain per §18.4.1: Active (đang hoạt động), Inactive (tạm ngưng)
    CONSTRAINT CHK_Venue_Status CHECK (VenueStatus IN ('Active', 'Inactive'))
);
