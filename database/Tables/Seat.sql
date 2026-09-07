CREATE TABLE Seat (
    SeatID INT IDENTITY(1,1) NOT NULL,
    ZoneID INT NOT NULL,
    VenueID INT NOT NULL,
    SeatCode VARCHAR(64) NOT NULL,
    SeatLabel NVARCHAR(255),
    -- BR50e: Seat bi EventSeat/Ticket lich su tham chieu nen khong the Hard Delete.
    -- Retired = ghe da thao do khi cai tao Venue, khong duoc chon vao kho ve moi (FR11).
    SeatStatus VARCHAR(32) NOT NULL CONSTRAINT DF_Seat_Status DEFAULT 'Active',

    -- ── VI TRI TRONG KHU (FR11a) ───────────────────────────────────────────
    --
    -- SeatCode la DINH DANH (duy nhat trong dia diem), khong phai vi tri:
    -- 'STD-023955-4' khong noi len ghe nam o dau. Hai cot duoi moi la vi tri.
    --
    -- Day cung la tang con thieu trong bo ba danh tinh ma moi he thong ban ve deu
    -- dung: KHU -> HANG -> GHE. Truoc thay doi nay he thong chi co KHU va GHE, nen
    -- khong the in ra mot dia chi cho ngoi ma nguoi thuong hieu duoc
    -- ('Khu A, hang C, ghe 12').
    --
    -- Toa do TUYET DOI cua ghe KHONG duoc luu, va do la co y: chung se sai ngay khi
    -- khu duoc dat lai vi tri, sinh ra hai nguon su that lech nhau. Vi tri thuc te
    -- = hop bao cua khu + goc xoay + o luoi nay. Khu co hinh bat thuong van bieu
    -- dien duoc bang cach chia thanh nhieu khu nho.
    SeatRowLabel     NVARCHAR(16) NULL,
    SeatColumnNumber INT NULL,

    CONSTRAINT CHK_Seat_Status CHECK (SeatStatus IN ('Active', 'Retired')),
    CONSTRAINT CHK_Seat_Column CHECK (SeatColumnNumber IS NULL OR SeatColumnNumber > 0),
    -- Hang va cot di cung nhau: chi mot trong hai thi khong dinh vi duoc.
    CONSTRAINT CHK_Seat_GridComplete CHECK (
        (SeatRowLabel IS NULL AND SeatColumnNumber IS NULL)
     OR (SeatRowLabel IS NOT NULL AND SeatColumnNumber IS NOT NULL)
    ),

    CONSTRAINT PK_Seat PRIMARY KEY CLUSTERED (SeatID),
    CONSTRAINT FK_Seat_Zone FOREIGN KEY (ZoneID) REFERENCES Zone(ZoneID),
    CONSTRAINT FK_Seat_Venue FOREIGN KEY (VenueID) REFERENCES Venue(VenueID),
    CONSTRAINT UQ_Seat_Venue_SeatCode UNIQUE (VenueID, SeatCode)
);
GO

-- Mot o luoi (hang, cot) trong mot khu chi duoc MOT ghe dang hoat dong chiem giu.
-- Khong co rang buoc nay thi hai ghe cung ve chong len nhau tren so do, va khach
-- khong biet minh vua dat cai nao.
--
-- Loc SeatStatus = 'Active' de ghe da thao do (Retired, FR11) van giu lai vi tri
-- lich su ma khong chan ghe moi lap vao dung cho do sau khi cai tao dia diem.
CREATE UNIQUE INDEX UIX_Seat_GridSlot
    ON Seat (ZoneID, SeatRowLabel, SeatColumnNumber)
    WHERE SeatRowLabel IS NOT NULL
      AND SeatColumnNumber IS NOT NULL
      AND SeatStatus = 'Active';
