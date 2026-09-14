-- ============================================================
-- VenueTemplateVersion (StagePass)
--
-- Phiên bản của một VenueTemplate. Draft sửa được tự do; Published là BẤT BIẾN —
-- không SP nào được phép UPDATE hình học của một version đã Published (chỉ có
-- thể tạo version kế tiếp từ nó). Đây là bất biến quan trọng nhất của toàn bộ
-- lớp StagePass: nếu Published sửa được, mọi ConcertMapRevision đã snapshot từ
-- nó không còn ý nghĩa "bất biến" nữa.
--
-- RowVer dùng cho optimistic concurrency (ETag) — KHÁC với UPDLOCK bi quan mà
-- Venue/Zone/Seat đang dùng. Lý do tách: sửa Venue/Zone/Seat là thao tác hiếm,
-- một Admin một lúc, UPDLOCK-chờ là đủ. Sửa VenueTemplateVersion.Draft là biên
-- tập trực quan, nhiều người có thể cùng mở — ETag cho phép phát hiện xung đột
-- ("ai đó vừa sửa, tải lại đi") thay vì bắt request thứ hai xếp hàng chờ khoá.
-- Xem docs/stagepass-architecture.md §4.4/D.1.
-- ============================================================
CREATE TABLE VenueTemplateVersion (
    VenueTemplateVersionID INT IDENTITY(1,1) NOT NULL,
    VenueTemplateID        INT NOT NULL,
    VersionNumber          INT NOT NULL,
    VersionStatus          VARCHAR(32) NOT NULL CONSTRAINT DF_VTV_Status DEFAULT 'Draft',
    AuthorUserID           INT NOT NULL,
    CreatedTimestamp       DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    PublishedTimestamp     DATETIME2(7) NULL,
    RowVer                 ROWVERSION NOT NULL,

    CONSTRAINT PK_VenueTemplateVersion PRIMARY KEY CLUSTERED (VenueTemplateVersionID),
    CONSTRAINT FK_VTV_Template FOREIGN KEY (VenueTemplateID) REFERENCES VenueTemplate(VenueTemplateID),
    CONSTRAINT FK_VTV_Author FOREIGN KEY (AuthorUserID) REFERENCES UserAccount(UserID),
    -- Số phiên bản tăng dần trong phạm vi template, không phải toàn hệ thống.
    CONSTRAINT UQ_VTV_Template_Version UNIQUE (VenueTemplateID, VersionNumber),
    CONSTRAINT CHK_VTV_VersionNumber CHECK (VersionNumber > 0),
    CONSTRAINT CHK_VTV_Status CHECK (VersionStatus IN ('Draft', 'Published', 'Retired')),
    -- PublishedTimestamp là dấu vết đối xứng với trạng thái: Draft thì chưa có
    -- mốc publish; Published/Retired thì bắt buộc phải có (Retired suy ra từ một
    -- version đã từng Published rồi mới bị nghỉ, không có đường Draft -> Retired
    -- thẳng — luật này thi hành ở SP, không phải CHECK, vì CHECK không biết được
    -- lịch sử chuyển trạng thái).
    CONSTRAINT CHK_VTV_PublishedTimestamp CHECK (
            (VersionStatus = 'Draft' AND PublishedTimestamp IS NULL)
         OR (VersionStatus IN ('Published', 'Retired') AND PublishedTimestamp IS NOT NULL)
    )
);
GO

-- Mỗi Template chỉ có MỘT Draft đang mở tại một thời điểm — tránh admin vô tình
-- tạo hai bản nháp song song rồi không biết bản nào là "phiên bản đang làm".
-- Muốn có bản nháp mới thì phải publish hoặc bỏ (Retired) bản Draft hiện có
-- trước. Filtered unique index vì bất biến chỉ áp cho đúng một trạng thái.
CREATE UNIQUE INDEX UIX_VTV_OneDraftPerTemplate
    ON VenueTemplateVersion (VenueTemplateID)
    WHERE VersionStatus = 'Draft';
