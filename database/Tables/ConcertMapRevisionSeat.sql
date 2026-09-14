-- ============================================================
-- ConcertMapRevisionSeat (StagePass)
--
-- Bản sao của TemplateSeat tại thời điểm snapshot — vị trí, hàng/số, hình học,
-- cờ accessible/companion đều là ảnh chụp bất biến. SeatID vẫn trỏ tới Seat vật
-- lý thật (để không phá vỡ Ticket/CheckIn/Refund vốn trỏ xuyên qua
-- EventSeat -> Seat), nhưng KHÔNG trỏ TemplateSeat nguồn — cùng nguyên tắc
-- "không phụ thuộc source sau khi snapshot" của các bảng revision khác.
--
-- EventSeatID là điểm nối duy nhất giữa lớp đồ hoạ StagePass và lớp tồn kho
-- EventSeat hiện có. NULL nghĩa là ghế có trên sơ đồ nhưng CHƯA được đưa vào
-- kho vé bán (đúng Phần 1: "ConcertMapSeat... map đến một EventSeat CHỈ KHI ghế
-- được đưa vào bán"). SP thay thế sp_AddEventSeats sẽ gán cột này trong cùng
-- transaction với việc tạo EventSeat.
--
-- BẤT BIẾN LIÊN BẢNG CẦN TRIGGER (không biểu diễn được bằng CHECK/FK):
--   EventSeat.ConcertID (qua EventSeatID) phải khớp Concert của chính
--   ConcertMapRevision này (qua ConcertMapRevisionID -> ConcertMapRevisionFloor
--   -> ConcertMapRevisionID -> ConcertMapRevision -> ConcertMap -> ConcertID).
--   Thi hành ở tầng SP lúc gán EventSeatID (cùng khuôn TRG_EventSeatVenue kiểm
--   tra Seat/Venue khớp Concert) — xem SP thay thế sp_AddEventSeats khi triển
--   khai tầng thủ tục.
-- ============================================================
CREATE TABLE ConcertMapRevisionSeat (
    ConcertMapRevisionSeatID    INT IDENTITY(1,1) NOT NULL,
    ConcertMapRevisionSectionID INT NOT NULL,
    SourceTemplateSeatID        INT NULL,   -- truy vết, cố ý không FK
    SeatID                      INT NOT NULL,
    SeatKey                     VARCHAR(64) NOT NULL,
    RowLabel                    NVARCHAR(16) NULL,
    SeatNumber                  INT NULL,
    GeometryJson                NVARCHAR(MAX) NULL,
    IsAccessible                BIT NOT NULL CONSTRAINT DF_CMRSeat_Accessible DEFAULT 0,
    IsCompanion                 BIT NOT NULL CONSTRAINT DF_CMRSeat_Companion DEFAULT 0,
    EventSeatID                 INT NULL,

    CONSTRAINT PK_CMRSeat PRIMARY KEY CLUSTERED (ConcertMapRevisionSeatID),
    CONSTRAINT FK_CMRSeat_Section FOREIGN KEY (ConcertMapRevisionSectionID)
        REFERENCES ConcertMapRevisionSection(ConcertMapRevisionSectionID),
    CONSTRAINT FK_CMRSeat_Seat FOREIGN KEY (SeatID) REFERENCES Seat(SeatID),
    CONSTRAINT FK_CMRSeat_EventSeat FOREIGN KEY (EventSeatID) REFERENCES EventSeat(EventSeatID),
    CONSTRAINT UQ_CMRSeat_Section_Key UNIQUE (ConcertMapRevisionSectionID, SeatKey),
    CONSTRAINT CHK_CMRSeat_Number CHECK (SeatNumber IS NULL OR SeatNumber > 0),
    CONSTRAINT CHK_CMRSeat_RowNumberTogether CHECK (
            (RowLabel IS NULL AND SeatNumber IS NULL)
         OR (RowLabel IS NOT NULL AND SeatNumber IS NOT NULL)
    ),
    CONSTRAINT CHK_CMRSeat_GeometryJson CHECK (GeometryJson IS NULL OR ISJSON(GeometryJson) = 1)
);
GO

-- Mỗi EventSeat chỉ được đúng một ConcertMapRevisionSeat đại diện — ngược lại sẽ
-- có hai vị trí trên sơ đồ cùng trỏ một hàng tồn kho, và khách chọn "ghế A" hay
-- "ghế B" trên sơ đồ thực ra lại đặt trùng một chỗ.
--
-- BẮT BUỘC là FILTERED INDEX (WHERE EventSeatID IS NOT NULL), KHÔNG phải UNIQUE
-- constraint thường: SQL Server coi hai giá trị NULL là TRÙNG NHAU trong một
-- UNIQUE constraint/index thường (khác PostgreSQL/Oracle, nơi NULL không bao
-- giờ bằng NULL). EventSeatID = NULL là trạng thái BÌNH THƯỜNG của mọi ghế chưa
-- đưa vào bán — một constraint không filter sẽ chặn nhầm dòng NULL thứ hai trở
-- đi, tức là mọi Concert có từ hai ghế chưa bán trở lên không dựng được sơ đồ.
-- Đã tái hiện lỗi này bằng thực nghiệm trước khi sửa (xem lịch sử commit).
-- Cùng khuôn UIX_Seat_GridSlot/UIX_TemplateSeat_GridSlot đã dùng cho đúng lý do
-- này.
CREATE UNIQUE INDEX UIX_CMRSeat_EventSeat
    ON ConcertMapRevisionSeat (EventSeatID)
    WHERE EventSeatID IS NOT NULL;
