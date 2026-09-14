-- ============================================================
-- ConcertMapRevisionSection (StagePass)
--
-- Bản sao của TemplateSection tại thời điểm snapshot — khu ghế của CHÍNH
-- revision này, bất biến kể cả khi TemplateSection nguồn bị sửa sau đó (Section
-- nguồn không sửa được khi version cha đã Published, nhưng vẫn giữ nguyên tắc
-- không phụ thuộc, phòng trường hợp version cha bị Retired/archive).
-- ============================================================
CREATE TABLE ConcertMapRevisionSection (
    ConcertMapRevisionSectionID INT IDENTITY(1,1) NOT NULL,
    ConcertMapRevisionFloorID   INT NOT NULL,
    SourceTemplateSectionID     INT NULL,   -- truy vết, cố ý không FK
    SectionKey                  VARCHAR(64) NOT NULL,
    SectionName                 NVARCHAR(255) NULL,
    GeometryJson                NVARCHAR(MAX) NOT NULL,

    CONSTRAINT PK_CMRSection PRIMARY KEY CLUSTERED (ConcertMapRevisionSectionID),
    CONSTRAINT FK_CMRSection_Floor FOREIGN KEY (ConcertMapRevisionFloorID)
        REFERENCES ConcertMapRevisionFloor(ConcertMapRevisionFloorID),
    CONSTRAINT UQ_CMRSection_Floor_Key UNIQUE (ConcertMapRevisionFloorID, SectionKey),
    CONSTRAINT CHK_CMRSection_GeometryJson CHECK (ISJSON(GeometryJson) = 1)
);
