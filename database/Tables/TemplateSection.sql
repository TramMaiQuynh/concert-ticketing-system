-- ============================================================
-- TemplateSection (StagePass)
--
-- Khu ghế trong một tầng — tương ứng Zone hiện tại, nhưng KHÔNG giới hạn hình
-- chữ nhật. Zone.ZoneX/Y/Width/Height/Rotation chỉ biểu diễn được rectangle đã
-- xoay; TemplateSection.GeometryJson biểu diễn được polygon tự do (khán đài
-- hình vòng cung, khu hình quạt theo bản vẽ thật).
--
-- ── QUY ƯỚC GeometryJson (v1) — DÙNG CHUNG cho TemplateObject, TemplateSection,
--    TemplateSeat, và các bảng ConcertMapRevision* tương ứng ──────────────────
--
-- Đơn vị: số trừu tượng, CÙNG hệ toạ độ với TemplateFloor.CanvasWidth/Height
-- (kế thừa nguyên tắc Venue.MapWidth/Height hiện tại — không phải mét/pixel).
--
-- {
--   "version": 1,
--   "shape": "rect" | "polygon",
--   "rotation": <độ, chỉ áp dụng khi shape = "rect">,
--   -- shape = "rect":
--   "x": <số>, "y": <số>, "width": <số>, "height": <số>,
--   -- shape = "polygon":
--   "points": [[x1,y1],[x2,y2], ...]   -- tối thiểu 3 đỉnh, thứ tự theo chu vi
-- }
--
-- "rect" là trường hợp CỤ THỂ của polygon 4 đỉnh, giữ riêng (không chuẩn hoá về
-- polygon ngay từ đầu) vì phần lớn khu trong thực tế vẫn là hình chữ nhật xoay —
-- giữ dạng rect cho phép trình biên tập tiếp tục dùng thao tác kéo/xoay đơn giản
-- (kế thừa nguyên vẹn ZoneLayoutEditor hiện có trong VenueMap.jsx) thay vì luôn
-- bắt người dùng vẽ từng đỉnh. Thuật toán va chạm áp dụng SAT cho cả hai dạng:
-- rect dùng công thức nửa-rộng/cao + sin/cos hiện có; polygon dùng SAT tổng quát
-- trên trục pháp tuyến từng cạnh (không dùng lại nguyên công thức rect).
-- ============================================================
CREATE TABLE TemplateSection (
    TemplateSectionID INT IDENTITY(1,1) NOT NULL,
    TemplateFloorID    INT NOT NULL,
    ZoneID             INT NOT NULL,           -- khu vật lý mà Section này biểu diễn
    SectionKey         VARCHAR(64) NOT NULL,   -- định danh ổn định, vd 'VIP', 'BALCONY-L'
    SectionName        NVARCHAR(255) NULL,
    GeometryJson       NVARCHAR(MAX) NOT NULL,

    CONSTRAINT PK_TemplateSection PRIMARY KEY CLUSTERED (TemplateSectionID),
    CONSTRAINT FK_TemplateSection_Floor FOREIGN KEY (TemplateFloorID) REFERENCES TemplateFloor(TemplateFloorID),
    CONSTRAINT FK_TemplateSection_Zone FOREIGN KEY (ZoneID) REFERENCES Zone(ZoneID),
    CONSTRAINT UQ_TemplateSection_Floor_Key UNIQUE (TemplateFloorID, SectionKey),
    CONSTRAINT CHK_TemplateSection_GeometryJson CHECK (ISJSON(GeometryJson) = 1)
);
