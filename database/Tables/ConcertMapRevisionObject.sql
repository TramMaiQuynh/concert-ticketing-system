-- ============================================================
-- ConcertMapRevisionObject (StagePass)
--
-- Bản sao của TemplateObject (sân khấu, lối đi, vật thể trang trí) tại thời
-- điểm snapshot. Xem ConcertMapRevisionFloor.sql cho lý do không FK tới bảng
-- Template nguồn.
-- ============================================================
CREATE TABLE ConcertMapRevisionObject (
    ConcertMapRevisionObjectID INT IDENTITY(1,1) NOT NULL,
    ConcertMapRevisionFloorID  INT NOT NULL,
    ObjectType                 VARCHAR(32) NOT NULL,
    Label                      NVARCHAR(255) NULL,
    GeometryJson               NVARCHAR(MAX) NOT NULL,
    ZIndex                     INT NOT NULL CONSTRAINT DF_CMRObject_ZIndex DEFAULT 0,

    CONSTRAINT PK_CMRObject PRIMARY KEY CLUSTERED (ConcertMapRevisionObjectID),
    CONSTRAINT FK_CMRObject_Floor FOREIGN KEY (ConcertMapRevisionFloorID)
        REFERENCES ConcertMapRevisionFloor(ConcertMapRevisionFloorID),
    CONSTRAINT CHK_CMRObject_Type CHECK (
        ObjectType IN ('Stage', 'Aisle', 'Wall', 'Entrance', 'Restroom', 'Bar', 'Text', 'Icon')
    ),
    CONSTRAINT CHK_CMRObject_GeometryJson CHECK (ISJSON(GeometryJson) = 1)
);
