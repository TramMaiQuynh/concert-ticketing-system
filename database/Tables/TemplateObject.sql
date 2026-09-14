-- ============================================================
-- TemplateObject (StagePass)
--
-- Vật thể trang trí/tham chiếu trên một tầng: sân khấu, lối đi, tường, cửa vào,
-- nhà vệ sinh, quầy bar, nhãn chữ. KHÔNG bán được — khác hẳn TemplateSection
-- (khu ghế, có inventory). Gộp 'Stage' vào đây thay vì giữ StageX/Y/W/H riêng
-- như Venue hiện tại, vì một tầng có thể cần nhiều vật thể tham chiếu cùng lúc
-- (sân khấu + lối thoát hiểm + quầy bar), không chỉ một sân khấu.
--
-- GeometryJson là JSON tự do có version nội bộ (rectangle/polygon/path/circle —
-- xem quy ước ở TemplateSection.sql). Chỉ ràng buộc ISJSON ở tầng CHECK; đúng
-- hình dạng bên trong do tầng ứng dụng validate, vì CHECK constraint của SQL
-- Server không parse được cấu trúc JSON tuỳ ý.
-- ============================================================
CREATE TABLE TemplateObject (
    TemplateObjectID INT IDENTITY(1,1) NOT NULL,
    TemplateFloorID  INT NOT NULL,
    ObjectType       VARCHAR(32) NOT NULL,
    Label            NVARCHAR(255) NULL,
    GeometryJson     NVARCHAR(MAX) NOT NULL,
    ZIndex           INT NOT NULL CONSTRAINT DF_TemplateObject_ZIndex DEFAULT 0,

    CONSTRAINT PK_TemplateObject PRIMARY KEY CLUSTERED (TemplateObjectID),
    CONSTRAINT FK_TemplateObject_Floor FOREIGN KEY (TemplateFloorID) REFERENCES TemplateFloor(TemplateFloorID),
    CONSTRAINT CHK_TemplateObject_Type CHECK (
        ObjectType IN ('Stage', 'Aisle', 'Wall', 'Entrance', 'Restroom', 'Bar', 'Text', 'Icon')
    ),
    CONSTRAINT CHK_TemplateObject_GeometryJson CHECK (ISJSON(GeometryJson) = 1)
);
