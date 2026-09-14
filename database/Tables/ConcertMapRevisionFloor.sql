-- ============================================================
-- ConcertMapRevisionFloor (StagePass)
--
-- Bản sao (snapshot) của TemplateFloor tại thời điểm tạo ConcertMapRevision.
-- SourceTemplateFloorID chỉ để truy vết — KHÔNG có FOREIGN KEY tới
-- TemplateFloor, đúng nguyên tắc "không phụ thuộc source sau khi snapshot"
-- (ConcertMapRevision.sql): nếu Admin xoá/archive template gốc sau này, dòng
-- snapshot này vẫn nguyên vẹn, không bị ảnh hưởng.
-- ============================================================
CREATE TABLE ConcertMapRevisionFloor (
    ConcertMapRevisionFloorID INT IDENTITY(1,1) NOT NULL,
    ConcertMapRevisionID      INT NOT NULL,
    SourceTemplateFloorID     INT NULL,   -- truy vết, cố ý không FK (xem ghi chú trên)
    FloorKey                  VARCHAR(64) NOT NULL,
    FloorName                 NVARCHAR(255) NULL,
    FloorOrder                INT NOT NULL,
    CanvasWidth                INT NOT NULL,
    CanvasHeight                INT NOT NULL,

    CONSTRAINT PK_CMRFloor PRIMARY KEY CLUSTERED (ConcertMapRevisionFloorID),
    CONSTRAINT FK_CMRFloor_Revision FOREIGN KEY (ConcertMapRevisionID)
        REFERENCES ConcertMapRevision(ConcertMapRevisionID),
    CONSTRAINT UQ_CMRFloor_Revision_Key UNIQUE (ConcertMapRevisionID, FloorKey),
    CONSTRAINT CHK_CMRFloor_CanvasSize CHECK (CanvasWidth > 0 AND CanvasHeight > 0),
    CONSTRAINT CHK_CMRFloor_Order CHECK (FloorOrder > 0)
);
