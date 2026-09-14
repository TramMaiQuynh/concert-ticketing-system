-- ============================================================
-- TemplateFloor (StagePass)
--
-- Một tầng/canvas riêng trong một VenueTemplateVersion. Nhà hát nhiều tầng và
-- sân vận động xếp khán đài chồng lên nhau theo chiều cao — một mặt phẳng duy
-- nhất (như Venue.MapWidth/Height hiện tại) không biểu diễn được điều đó.
-- Renderer vẽ đúng MỘT tầng tại một thời điểm, đúng cách các trang bán vé thật
-- vẽ khán phòng.
-- ============================================================
CREATE TABLE TemplateFloor (
    TemplateFloorID        INT IDENTITY(1,1) NOT NULL,
    VenueTemplateVersionID INT NOT NULL,
    FloorKey                VARCHAR(64) NOT NULL,  -- định danh ổn định, vd 'ground', 'balcony'
    FloorName               NVARCHAR(255) NULL,
    FloorOrder              INT NOT NULL,          -- thứ tự hiển thị/chọn tầng
    CanvasWidth             INT NOT NULL,
    CanvasHeight             INT NOT NULL,

    CONSTRAINT PK_TemplateFloor PRIMARY KEY CLUSTERED (TemplateFloorID),
    CONSTRAINT FK_TemplateFloor_Version FOREIGN KEY (VenueTemplateVersionID)
        REFERENCES VenueTemplateVersion(VenueTemplateVersionID),
    CONSTRAINT UQ_TemplateFloor_Version_Key UNIQUE (VenueTemplateVersionID, FloorKey),
    CONSTRAINT UQ_TemplateFloor_Version_Order UNIQUE (VenueTemplateVersionID, FloorOrder),
    CONSTRAINT CHK_TemplateFloor_CanvasSize CHECK (CanvasWidth > 0 AND CanvasHeight > 0),
    CONSTRAINT CHK_TemplateFloor_Order CHECK (FloorOrder > 0)
);
