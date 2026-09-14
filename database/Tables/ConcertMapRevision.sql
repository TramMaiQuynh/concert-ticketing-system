-- ============================================================
-- ConcertMapRevision (StagePass)
--
-- Snapshot BẤT BIẾN của một VenueTemplateVersion tại thời điểm Organizer chọn
-- nó cho Concert. "Snapshot" nghĩa là dữ liệu hình học được SAO CHÉP sang các
-- bảng ConcertMapRevision*Floor/Object/Section/Seat — không phải một view hay
-- tham chiếu sống tới TemplateFloor/Section/Seat. Lý do bắt buộc phải sao chép:
-- nếu Venue publish version mới sau khi Concert đã bán vé, đọc thẳng qua tham
-- chiếu sẽ làm vé đã phát hành đột nhiên hiển thị theo layout mới — đúng vấn đề
-- Phần 1 nêu ra ("đổi stage, zone hoặc cải tạo venue có thể làm concert cũ hiển
-- thị theo layout mới").
--
-- Draft: đang cấu hình ticket category/inventory, sửa được (nhưng KHÔNG sửa
--        hình học — hình học đã bất biến từ lúc snapshot).
-- Locked: đã OnSale, là revision DUY NHẤT được API public đọc để bán.
-- Replaced: revision cũ, không còn Locked (chỉ xảy ra khi tạo revision kế tiếp
--        cho cùng Concert — trường hợp hiếm, cần audit riêng, xem
--        docs/stagepass-architecture.md §4.3).
-- ============================================================
CREATE TABLE ConcertMapRevision (
    ConcertMapRevisionID         INT IDENTITY(1,1) NOT NULL,
    ConcertMapID                 INT NOT NULL,
    SourceVenueTemplateVersionID INT NOT NULL,
    RevisionNumber               INT NOT NULL,
    RevisionStatus               VARCHAR(32) NOT NULL CONSTRAINT DF_CMR_Status DEFAULT 'Draft',
    SnapshotTimestamp            DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    LockedTimestamp               DATETIME2(7) NULL,
    RowVer                        ROWVERSION NOT NULL,

    CONSTRAINT PK_ConcertMapRevision PRIMARY KEY CLUSTERED (ConcertMapRevisionID),
    CONSTRAINT FK_CMR_Map FOREIGN KEY (ConcertMapID) REFERENCES ConcertMap(ConcertMapID),
    -- Nguồn snapshot chỉ để TRUY VẾT (biết revision này sinh từ template version
    -- nào) — sau khi snapshot, dữ liệu hình học không còn phụ thuộc bảng nguồn,
    -- đúng nguyên tắc Phần 1: "có source ID để truy vết nhưng không phụ thuộc
    -- source sau khi snapshot".
    CONSTRAINT FK_CMR_SourceVersion FOREIGN KEY (SourceVenueTemplateVersionID)
        REFERENCES VenueTemplateVersion(VenueTemplateVersionID),
    CONSTRAINT UQ_CMR_Map_Number UNIQUE (ConcertMapID, RevisionNumber),
    CONSTRAINT CHK_CMR_RevisionNumber CHECK (RevisionNumber > 0),
    CONSTRAINT CHK_CMR_Status CHECK (RevisionStatus IN ('Draft', 'Locked', 'Replaced')),
    CONSTRAINT CHK_CMR_LockedTimestamp CHECK (
            (RevisionStatus = 'Draft' AND LockedTimestamp IS NULL)
         OR (RevisionStatus IN ('Locked', 'Replaced') AND LockedTimestamp IS NOT NULL)
    )
);
GO

-- "Chỉ một revision có thể được dùng để bán" (Phần 1) — đúng một Locked tại một
-- thời điểm cho mỗi Concert. Cùng khuôn UIX_VTV_OneDraftPerTemplate ở trên: bất
-- biến chỉ áp cho một trạng thái cụ thể nên dùng filtered unique index thay vì
-- một cột trạng thái ở bảng cha.
CREATE UNIQUE INDEX UIX_CMR_OneLockedPerMap
    ON ConcertMapRevision (ConcertMapID)
    WHERE RevisionStatus = 'Locked';
