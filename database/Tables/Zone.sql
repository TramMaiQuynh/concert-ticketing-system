CREATE TABLE Zone (
    ZoneID INT IDENTITY(1,1) NOT NULL,
    VenueID INT NOT NULL,
    ZoneCode VARCHAR(64) NOT NULL,
    ZoneName NVARCHAR(255),
    ZoneDescription NVARCHAR(500),
    -- BR50e: Zone bi Seat/EventSeat lich su tham chieu nen khong the Hard Delete.
    ZoneStatus VARCHAR(32) NOT NULL CONSTRAINT DF_Zone_Status DEFAULT 'Active',

    -- ── HINH HOC CUA KHU (FR11a) ───────────────────────────────────────────
    --
    -- ZoneType phan biet hai ban chat khac han nhau, dung nhu cach cac he thong
    -- so do cho ngoi thuong mai lam:
    --   'Seated'            khu co ghe danh so — ban theo tung ghe.
    --   'GeneralAdmission'  khu dung/tu do — ban theo SUC CHUA, khong co dong
    --                       Seat nao. Concert gan nhu luon co loai khu nay (pit
    --                       truoc san khau, bai co). Tao hang nghin dong Seat gia
    --                       de mo phong no la sai ban chat va lang phi.
    --
    -- ZoneLevel la tang/khan dai (1 = tang tret). Nha hat va san van dong xep khu
    -- chong len nhau theo chieu cao; mot mat phang phang khong bieu dien duoc dieu
    -- do. Renderer hien tung tang mot, dung nhu cac trang ban ve that.
    --
    -- ZoneX/Y/Width/Height la hop bao cua khu trong he toa do cua Venue.
    -- ZoneRotation (do) cho phep xoay khu huong ve san khau — bat buoc voi khan
    -- dai hinh vong cung; thieu no thi moi dia diem deu bi ep thanh luoi vuong goc.
    --
    -- VI SAO KHONG DUNG 'Trai/Giua/Phai' HAY 'thu tu tinh tu san khau': nhung cach
    -- mo ta do chi dung cho MOT kieu khan phong chu nhat. Chung vo nghia voi san
    -- van dong vong 360 do, nha hat nhieu tang, hay club co khu dung. Toa do thi
    -- phu duoc moi hinh dang dia diem — va do la ly do cac he thong that dung toa do.
    ZoneType     VARCHAR(24) NOT NULL CONSTRAINT DF_Zone_Type DEFAULT 'Seated',
    ZoneLevel    INT NULL,
    ZoneX        INT NULL,
    ZoneY        INT NULL,
    ZoneWidth    INT NULL,
    ZoneHeight   INT NULL,
    ZoneRotation DECIMAL(6, 2) NULL,
    ZoneCapacity INT NULL,

    CONSTRAINT CHK_Zone_Status CHECK (ZoneStatus IN ('Active', 'Retired')),
    CONSTRAINT CHK_Zone_Type CHECK (ZoneType IN ('Seated', 'GeneralAdmission')),
    CONSTRAINT CHK_Zone_Level CHECK (ZoneLevel IS NULL OR ZoneLevel > 0),
    CONSTRAINT CHK_Zone_Size CHECK (
            (ZoneWidth  IS NULL OR ZoneWidth  > 0)
        AND (ZoneHeight IS NULL OR ZoneHeight > 0)
    ),
    CONSTRAINT CHK_Zone_Rotation CHECK (
        ZoneRotation IS NULL OR (ZoneRotation > -360 AND ZoneRotation < 360)
    ),
    -- Hop bao phai day du hoac khong co gi: mot khu chi biet X ma khong biet Width
    -- thi khong ve duoc, va de lot vao co so du lieu se sinh ra so do vo.
    CONSTRAINT CHK_Zone_BoxComplete CHECK (
        (ZoneX IS NULL AND ZoneY IS NULL AND ZoneWidth IS NULL AND ZoneHeight IS NULL)
     OR (ZoneX IS NOT NULL AND ZoneY IS NOT NULL AND ZoneWidth IS NOT NULL AND ZoneHeight IS NOT NULL)
    ),
    -- Toa do khong duoc am: mot khu tai X=-50 nam mot phan ngoai mat phang tu dinh
    -- nghia, bat ke mat phang lon bao nhieu. Truoc khi co rang buoc nay, tang bang
    -- chap nhan ZoneX/Y am - da kiem chung bang INSERT truc tiep thanh cong.
    -- Chi kiem duoc TOA DO cua rieng Zone o day: "Zone nam TRONG Venue map" la bat
    -- bien khac bang (Zone.ZoneX+Width so voi Venue.MapWidth) nen CHECK cua SQL
    -- Server khong the bieu dien - bat bien do da duoc bao ve boi sp_CreateZone/
    -- sp_UpdateZone, dong bo bang WITH (UPDLOCK) tren Venue.
    CONSTRAINT CHK_Zone_PositionNonNegative CHECK (
        ZoneX IS NULL OR (ZoneX >= 0 AND ZoneY >= 0)
    ),
    -- Suc chua chi thuoc ve khu ve dung, va khu ve dung thi bat buoc phai co: khong
    -- co so nay thi khu do khong ban duoc gi, vi no khong co ghe de dem.
    CONSTRAINT CHK_Zone_CapacityMatchesType CHECK (
        (ZoneType = 'GeneralAdmission' AND ZoneCapacity IS NOT NULL AND ZoneCapacity > 0)
     OR (ZoneType <> 'GeneralAdmission' AND ZoneCapacity IS NULL)
    ),

    CONSTRAINT PK_Zone PRIMARY KEY CLUSTERED (ZoneID),
    CONSTRAINT FK_Zone_Venue FOREIGN KEY (VenueID) REFERENCES Venue(VenueID),
    CONSTRAINT UQ_Zone_Venue_ZoneCode UNIQUE (VenueID, ZoneCode)
);
