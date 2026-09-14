USE ConcertTicketingDB;
GO

/* ╔══════════════════════════════════════════════════════════════════════════╗
   ║  LỖI 2 — DIRTY READ (Đọc dữ liệu bẩn)                                    ║
   ╚══════════════════════════════════════════════════════════════════════════╝

   ── TÌNH HUỐNG ────────────────────────────────────────────────────────────
   Nhân viên A sửa mức giảm giá của một chương trình khuyến mãi: gõ nhầm 90
   thay vì 9. Anh ta chưa bấm xác nhận — giao tác đang mở, CHƯA COMMIT.

   Cùng lúc đó, nhân viên B chạy báo cáo tổng hợp các chương trình khuyến mãi
   để gửi cho ban giám đốc.

   ── TƯƠNG TRANH ────────────────────────────────────────────────────────────
   Nếu phiên đọc của B chạy ở mức cô lập READ UNCOMMITTED (hoặc dùng gợi ý
   NOLOCK), B sẽ đọc được giá trị 90 mà A đang sửa dở — một giá trị CHƯA HỀ
   TỒN TẠI CHÍNH THỨC trong database.

   Ngay sau đó A nhận ra gõ nhầm và ROLLBACK. Giá trị 90 biến mất vĩnh viễn,
   coi như chưa từng có. Nhưng B đã kịp đọc và đã kịp đưa vào báo cáo.

   ── HẬU QUẢ ───────────────────────────────────────────────────────────────
   Báo cáo gửi ban giám đốc ghi mức giảm 90%, trong khi thực tế hệ thống chưa
   bao giờ áp mức đó. Không cách nào đối chiếu lại được, vì trong database
   không còn dấu vết nào của con số 90.

   ────────────────────────────────
   Hệ thống ĐÃ PHÒNG ĐƯỢC lỗi này: toàn bộ mã nguồn KHÔNG dùng
   NOLOCK hay READ UNCOMMITTED ở bất kỳ đâu, và SQL Server mặc định chạy ở
   mức READ COMMITTED. Demo dưới đây cố tình HẠ mức cô lập xuống để cho thấy
   điều gì SẼ xảy ra nếu lập trình viên dùng NOLOCK cho "chạy nhanh hơn".

   Khối so sánh cuối sẽ chứng minh: ở mức mặc định, phiên đọc bị CHẶN LẠI
   chứ không đọc được rác.
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  CHUẨN BỊ  ██████████████████
   Tạo một Promotion RIÊNG cho demo này (đánh dấu bằng tên, không phụ thuộc
   PromotionID cụ thể nào), để không đụng tới khuyến mãi thật đang chạy và
   để chạy lại demo bao nhiêu lần cũng không lệch kết quả.
   ────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DELETE p FROM dbo.Promotion p WHERE p.PromotionName = N'DEMO Loi 2 - Dirty Read'
    AND NOT EXISTS (SELECT 1 FROM dbo.BookingPromotionApplication bpa WHERE bpa.PromotionID = p.PromotionID);

DECLARE @ConcertID INT = (SELECT TOP 1 ConcertID FROM dbo.Concert ORDER BY ConcertID);
IF @ConcertID IS NULL THROW 52000, N'Can it nhat mot Concert trong he thong de chay demo.', 1;

INSERT INTO dbo.Promotion
    (ConcertID, PromotionName, PromotionDescription, DiscountType, DiscountValue,
     StartDatetime, EndDatetime, PromotionStatus, UsageLimit, CodeRequiredFlag)
VALUES
    (@ConcertID, N'DEMO Loi 2 - Dirty Read', N'Du lieu demo cho kich ban dirty read',
     'Percentage', 9, DATEADD(DAY, -1, SYSDATETIME()), DATEADD(DAY, 30, SYSDATETIME()),
     'Active', NULL, 0);

SELECT PromotionID, PromotionName, DiscountValue
FROM   dbo.Promotion WHERE PromotionName = N'DEMO Loi 2 - Dirty Read';
GO


/* ██████████████████  PHIÊN A — người sửa nhầm rồi hủy  ██████████████████ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

SELECT 'A' AS Phien, 'Truoc khi sua' AS Buoc, DiscountValue AS MucGiam
FROM   dbo.Promotion WHERE PromotionName = N'DEMO Loi 2 - Dirty Read';

BEGIN TRANSACTION;

    -- A go nham 90 thay vi 9. Giao tac CHUA commit.
    UPDATE dbo.Promotion
    SET    DiscountValue = 90
    WHERE  PromotionName = N'DEMO Loi 2 - Dirty Read';

    SELECT 'A' AS Phien, 'Da sua (CHUA COMMIT)' AS Buoc, 90 AS MucGiam;

    -- Giu giao tac mo. Day la luc du lieu dang o trang thai "ban":
    -- da ghi vao trang du lieu nhung chua duoc xac nhan.
    WAITFOR DELAY '00:00:12';

-- A phat hien go nham va HUY BO. Gia tri 90 coi nhu chua tung ton tai.
ROLLBACK TRANSACTION;

SELECT 'A' AS Phien, 'Da ROLLBACK' AS Buoc, DiscountValue AS MucGiamThucTe
FROM   dbo.Promotion WHERE PromotionName = N'DEMO Loi 2 - Dirty Read';
GO


/* ██████████████████  PHIÊN B — người chạy báo cáo  ██████████████████
   TRONG LÚC PHIÊN A ĐANG CHỜ.
   ──────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

/* ── Trường hợp 1: lập trình viên dùng READ UNCOMMITTED cho "nhanh" ──────── */
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

SELECT 'B' AS Phien,
       'READ UNCOMMITTED' AS MucCoLap,
       DiscountValue      AS DocDuoc,
       '<<< DIRTY READ: doc duoc so A dang sua do, chua commit' AS GhiChu
FROM   dbo.Promotion WHERE PromotionName = N'DEMO Loi 2 - Dirty Read';

/* ── Trường hợp 2: mức mặc định của hệ thống ─────────────────────────────
   Câu lệnh dưới đây sẽ BỊ CHẶN (treo) cho đến khi phiên A kết thúc, vì nó
   phải chờ khóa. Đây chính là cơ chế bảo vệ: thà chờ còn hơn đọc rác.       */
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

SELECT 'B' AS Phien,
       'READ COMMITTED' AS MucCoLap,
       DiscountValue    AS DocDuoc,
       'Phai CHO A ket thuc moi doc duoc -> khong bao gio thay so 90' AS GhiChu
FROM   dbo.Promotion WHERE PromotionName = N'DEMO Loi 2 - Dirty Read';
GO


/* ── CÁCH KHẮC PHỤC ────────────────────────────────────────────────────────

   Không làm gì cả — mức mặc định READ COMMITTED đã chặn sẵn lỗi này.

   Điều cần làm là KHÔNG BAO GIỜ thêm NOLOCK hay READ UNCOMMITTED vào truy vấn
   nghiệp vụ, kể cả khi bị áp lực về tốc độ. Nhiều người dùng NOLOCK như một
   mẹo tăng tốc mà không biết cái giá phải trả là đọc được dữ liệu chưa commit,
   dữ liệu sắp bị hủy, thậm chí đọc trùng hoặc sót dòng khi trang dữ liệu đang
   được sắp xếp lại.

   Kiểm chứng trong mã nguồn: tìm toàn bộ thư mục database/ không có kết quả
   nào cho NOLOCK hay READ UNCOMMITTED.
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  DỌN DẸP  ██████████████████ */
SET NOCOUNT ON;
DELETE p FROM dbo.Promotion p WHERE p.PromotionName = N'DEMO Loi 2 - Dirty Read'
    AND NOT EXISTS (SELECT 1 FROM dbo.BookingPromotionApplication bpa WHERE bpa.PromotionID = p.PromotionID);
GO
