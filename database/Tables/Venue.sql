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
    CONSTRAINT CHK_Venue_StageSize CHECK (
            (StageWidth  IS NULL OR StageWidth  > 0)
        AND (StageHeight IS NULL OR StageHeight > 0)
    ),
    -- San khau chi co nghia khi da co mat phang chua no.
    CONSTRAINT CHK_Venue_StageNeedsMap CHECK (
        StageX IS NULL OR (MapWidth IS NOT NULL AND MapHeight IS NOT NULL)
    ),
    CONSTRAINT PK_Venue PRIMARY KEY CLUSTERED (VenueID),
    -- Domain per §18.4.1: Active (đang hoạt động), Inactive (tạm ngưng)
    CONSTRAINT CHK_Venue_Status CHECK (VenueStatus IN ('Active', 'Inactive'))
);
