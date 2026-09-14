-- ============================================================
-- VenueTemplate (StagePass — sơ đồ có phiên bản, xem docs/stagepass-architecture.md)
--
-- Identity ổn định cho MỘT cách bố trí của một Venue: 'Theatre', 'End-stage',
-- 'In-the-round'... Một Venue có nhiều template vì cùng một địa điểm có thể được
-- dàn dựng khác nhau tuỳ tour/production (khác sân khấu, khác lối đi). Bản thân
-- VenueTemplate KHÔNG chứa hình học — hình học nằm ở VenueTemplateVersion trở
-- xuống, vì hình học phải có phiên bản (Draft sửa được, Published bất biến) còn
-- identity của template thì không cần.
--
-- Đây là bảng THÊM MỚI, không thay thế Zone/Seat: Zone/Seat/EventSeat tiếp tục là
-- dữ liệu nghiệp vụ (định danh ghế, tồn kho bán vé) như hiện tại. VenueTemplate
-- trở xuống là lớp đồ hoạ/snapshot bổ sung, phục vụ sơ đồ dạng polygon nhiều tầng
-- — Zone/Seat vẫn dùng được nguyên vẹn cho các Venue không cần mức độ đó.
-- ============================================================
CREATE TABLE VenueTemplate (
    VenueTemplateID   INT IDENTITY(1,1) NOT NULL,
    VenueID           INT NOT NULL,
    TemplateName      NVARCHAR(255) NOT NULL,
    TemplateStatus    VARCHAR(32) NOT NULL CONSTRAINT DF_VenueTemplate_Status DEFAULT 'Active',
    CreatedTimestamp  DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedTimestamp  DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),

    CONSTRAINT PK_VenueTemplate PRIMARY KEY CLUSTERED (VenueTemplateID),
    CONSTRAINT FK_VenueTemplate_Venue FOREIGN KEY (VenueID) REFERENCES Venue(VenueID),
    -- Tên template duy nhất trong phạm vi Venue, tránh hai bản ghi cùng tên
    -- 'Theatre' gây nhầm lẫn khi Organizer chọn.
    CONSTRAINT UQ_VenueTemplate_Venue_Name UNIQUE (VenueID, TemplateName),
    -- Active: đang dùng được để tạo version mới / chọn cho concert. Archived: giữ
    -- lại lịch sử (version cũ vẫn còn Published có thể đang được concert cũ tham
    -- chiếu) nhưng không hiện ra cho lựa chọn mới — cùng khuôn BR50e (Zone/Seat/
    -- Venue không Hard Delete vì bị dữ liệu lịch sử tham chiếu).
    CONSTRAINT CHK_VenueTemplate_Status CHECK (TemplateStatus IN ('Active', 'Archived'))
);
