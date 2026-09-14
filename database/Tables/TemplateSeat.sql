-- ============================================================
-- TemplateSeat (StagePass)
--
-- Ghế trong một TemplateSection, tham chiếu identity Seat hiện có (SeatID) —
-- KHÔNG tạo một hệ định danh ghế song song. Đây là ràng buộc tích hợp bắt buộc:
-- EventSeat/Ticket/Booking/CheckIn/Refund toàn bộ trỏ tới Seat, nên bất kỳ ghế
-- nào xuất hiện trên sơ đồ StagePass cũng phải LÀ một Seat thật, không phải một
-- bản sao độc lập.
--
-- ── VỊ TRÍ: mặc định suy từ lưới, không bắt buộc toạ độ tuyệt đối ───────────
--
-- Quyết định kiến trúc (docs/stagepass-architecture.md §4.2, Lựa chọn 1): kế
-- thừa nguyên tắc đã có ở Seat.SeatRowLabel/SeatColumnNumber — vị trí MẶC ĐỊNH
-- là một ô lưới (RowLabel, SeatNumber), tính lại lúc render từ hộp bao của
-- TemplateSection, không lưu toạ độ tuyệt đối cố định. Lý do giữ nguyên: toạ độ
-- tuyệt đối sẽ sai ngay khi Section bị dời/xoay, sinh ra hai nguồn sự thật lệch
-- nhau — đúng lý do Seat.sql đã lập luận cho ghế hiện tại.
--
-- GeometryJson CHỈ set khi ghế nằm trên hàng cong/bàn tròn — nơi phép nội suy
-- lưới vuông góc không áp dụng được. Khi NULL, renderer dùng đúng công thức nội
-- suy ô lưới hiện có trong SeatMap.jsx (ZoneSeats: ô 44 đơn vị mỗi hàng/cột).
-- Khi có GeometryJson, nó ghi đè cách tính từ lưới cho đúng ghế đó.
--
-- ── DUY NHẤT MỘT SEATID TRONG MỘT PHIÊN BẢN — thi hành ở SP, không phải CHECK ──
--
-- Theo thiết kế: "Mỗi SeatID chỉ được xuất hiện một lần trong một template
-- version". Phạm vi là VenueTemplateVersion, không phải toàn bảng — cùng một
-- Seat vật lý CÓ THỂ xuất hiện ở hai template KHÁC NHAU của cùng Venue (vd.
-- 'Theatre' và 'End-stage' đều dùng lại ghế khán đài cố định, chỉ khác khu sàn
-- trước sân khấu). Vì phạm vi "trong một version" đòi hỏi JOIN qua
-- Section -> Floor -> Version, một UNIQUE constraint đơn giản trên cột SeatID
-- của bảng này không biểu diễn được điều đó (sẽ cấm nhầm cả trường hợp hợp lệ ở
-- trên). Ràng buộc này thi hành trong SP tạo/sửa TemplateSeat bằng
-- WITH (UPDLOCK, HOLDLOCK) JOIN qua ba bảng, đúng khuôn sp_CreateSeat hiện tại
-- đang khoá key-range để chống trùng SeatCode trong Zone.
-- ============================================================
CREATE TABLE TemplateSeat (
    TemplateSeatID    INT IDENTITY(1,1) NOT NULL,
    TemplateSectionID INT NOT NULL,
    SeatID            INT NOT NULL,
    SeatKey           VARCHAR(64) NOT NULL,   -- định danh ổn định trong Section, vd SeatCode
    RowLabel          NVARCHAR(16) NULL,
    SeatNumber        INT NULL,
    GeometryJson      NVARCHAR(MAX) NULL,     -- NULL = suy từ lưới; xem ghi chú trên
    IsAccessible      BIT NOT NULL CONSTRAINT DF_TemplateSeat_Accessible DEFAULT 0,
    IsCompanion       BIT NOT NULL CONSTRAINT DF_TemplateSeat_Companion DEFAULT 0,

    CONSTRAINT PK_TemplateSeat PRIMARY KEY CLUSTERED (TemplateSeatID),
    CONSTRAINT FK_TemplateSeat_Section FOREIGN KEY (TemplateSectionID) REFERENCES TemplateSection(TemplateSectionID),
    CONSTRAINT FK_TemplateSeat_Seat FOREIGN KEY (SeatID) REFERENCES Seat(SeatID),
    CONSTRAINT UQ_TemplateSeat_Section_Key UNIQUE (TemplateSectionID, SeatKey),
    CONSTRAINT CHK_TemplateSeat_Number CHECK (SeatNumber IS NULL OR SeatNumber > 0),
    -- Hàng và số thứ tự đi cùng nhau — cùng bất biến CHK_Seat_GridComplete của
    -- Seat hiện tại.
    CONSTRAINT CHK_TemplateSeat_RowNumberTogether CHECK (
            (RowLabel IS NULL AND SeatNumber IS NULL)
         OR (RowLabel IS NOT NULL AND SeatNumber IS NOT NULL)
    ),
    CONSTRAINT CHK_TemplateSeat_GeometryJson CHECK (GeometryJson IS NULL OR ISJSON(GeometryJson) = 1)
);
GO

-- Một ô lưới (hàng, số) trong một Section chỉ một ghế chiếm — cùng vai trò với
-- UIX_Seat_GridSlot hiện có trên Seat, chỉ khác phạm vi là TemplateSection thay
-- vì Zone. Không lọc theo trạng thái Active/Retired vì TemplateSeat không có
-- khái niệm đó — TemplateSection thuộc một VenueTemplateVersion CỤ THỂ, và
-- version Retired không còn được sửa hay tạo mới, nên không có "ghế cũ đã ngừng
-- dùng" cần loại trừ trong phạm vi một version.
CREATE UNIQUE INDEX UIX_TemplateSeat_GridSlot
    ON TemplateSeat (TemplateSectionID, RowLabel, SeatNumber)
    WHERE RowLabel IS NOT NULL AND SeatNumber IS NOT NULL;
