USE ConcertTicketingDB;
GO

/* ╔══════════════════════════════════════════════════════════════════════════╗
   ║  LỖI 4 — PHANTOM READ (Đọc bóng ma)                                      ║
   ╚══════════════════════════════════════════════════════════════════════════╝

   ── TÌNH HUỐNG ────────────────────────────────────────────────────────────
   Công ty có quy định nội bộ: MỖI CHƯƠNG TRÌNH KHUYẾN MÃI CHỈ ĐƯỢC PHÁT
   TỐI ĐA 2 MÃ GIẢM GIÁ, để kiểm soát ngân sách marketing.

   Quy định này không được cài thành ràng buộc trong database, mà do phần mềm
   tự kiểm tra: trước khi thêm mã mới thì ĐẾM xem đã có bao nhiêu mã.

   Hai nhân viên A và B cùng được giao thêm mã cho một chương trình khuyến
   mãi demo (hiện đang có sẵn 1 mã). Cả hai cùng thao tác một lúc.

   ── TƯƠNG TRANH ────────────────────────────────────────────────────
   Khác với ba lỗi trước — vốn tranh nhau trên MỘT DÒNG cụ thể — lỗi này tranh
   nhau trên MỘT TẬP HỢP DÒNG (một khoảng dữ liệu).

       A đếm  → thấy 1 mã  → kết luận "còn chỗ, thêm được"
       B đếm  → cũng thấy 1 mã → cũng kết luận "còn chỗ, thêm được"
       B thêm → giờ có 2 mã, B commit
       A thêm → giờ có 3 mã

   Dòng mà B chèn vào chính là "bóng ma" (phantom): lúc A đếm thì nó chưa tồn
   tại, nên A không thể nhìn thấy để mà tính vào. Nhưng khi A thực thi thì nó
   đã ở đó rồi.

   Nguyên nhân kỹ thuật: ở mức READ COMMITTED, câu đếm chỉ khóa những dòng nó
   đọc được TẠI THỜI ĐIỂM ĐÓ, và nhả khóa ngay sau khi đếm xong. Nó KHÔNG khóa
   được "khoảng trống" — tức là không ngăn được dòng mới chèn vào khoảng đó.

   ── HẬU QUẢ ───────────────────────────────────────────────────────────────
   Chương trình có 3 mã, vượt quy định 2 mã. Ngân sách marketing bị phát vượt
   50%. Không có ràng buộc nào trong database bắt được, vì quy định này chỉ
   tồn tại trong tầng phần mềm — và tầng phần mềm đã kiểm tra trên một bức ảnh
   dữ liệu đã hết hạn.

   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  CHUẨN BỊ  ██████████████████
   Tạo một Promotion RIÊNG cho demo (đánh dấu bằng tên, không phụ thuộc
   PromotionID cụ thể), xoá sạch mọi mã cũ của nó rồi đặt lại đúng 1 mã nền,
   để số đếm ban đầu luôn là 1 — không phụ thuộc dữ liệu rác của lần chạy
   trước hay của demo khác.
   Nhờ vậy: A đếm 1 → thêm được, B đếm 1 → cũng thêm được, kết quả ra 3 mã.
   ────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @ConcertID INT = (SELECT TOP 1 ConcertID FROM dbo.Concert ORDER BY ConcertID);
IF @ConcertID IS NULL THROW 54000, N'Can it nhat mot Concert trong he thong de chay demo.', 1;

-- Xoa sach Promotion demo cu (va cac ma cua no) neu con sot tu lan chay truoc
DELETE dc FROM dbo.DiscountCode dc
JOIN   dbo.Promotion p ON p.PromotionID = dc.PromotionID
WHERE  p.PromotionName = N'DEMO Loi 4 - Phantom Read'
  AND  NOT EXISTS (SELECT 1 FROM dbo.BookingPromotionApplication bpa WHERE bpa.DiscountCodeID = dc.DiscountCodeID);

DELETE p FROM dbo.Promotion p
WHERE  p.PromotionName = N'DEMO Loi 4 - Phantom Read'
  AND  NOT EXISTS (SELECT 1 FROM dbo.DiscountCode dc WHERE dc.PromotionID = p.PromotionID);

INSERT INTO dbo.Promotion
    (ConcertID, PromotionName, PromotionDescription, DiscountType, DiscountValue,
     StartDatetime, EndDatetime, PromotionStatus, UsageLimit, CodeRequiredFlag)
VALUES
    (@ConcertID, N'DEMO Loi 4 - Phantom Read', N'Du lieu demo cho kich ban phantom read',
     'Fixed Amount', 100000, SYSDATETIME(), DATEADD(DAY, 30, SYSDATETIME()), 'Active', NULL, 1);

DECLARE @PromotionID INT = (SELECT PromotionID FROM dbo.Promotion WHERE PromotionName = N'DEMO Loi 4 - Phantom Read');

INSERT INTO dbo.DiscountCode
    (PromotionID, CodeValue, CodeStatus, ValidFromDatetime, ValidToDatetime,
     GlobalUsageLimit, PerCustomerUsageLimit, ReservedUsageCount, ConsumedUsageCount)
SELECT @PromotionID, 'MA-NEN', 'Active', StartDatetime, EndDatetime, NULL, NULL, 0, 0
FROM   dbo.Promotion WHERE PromotionID = @PromotionID;

SELECT 'Da chuan bi' AS TrangThai,
       COUNT(*)      AS SoMaHienCo,
       2             AS QuyDinhToiDa
FROM   dbo.DiscountCode WHERE PromotionID = @PromotionID;
GO


/* ██████████████████  PHIÊN A — nhân viên thứ nhất  ██████████████████ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @PromotionID INT = (SELECT PromotionID FROM dbo.Promotion WHERE PromotionName = N'DEMO Loi 4 - Phantom Read');
DECLARE @soMaA INT, @vfA DATETIME2(7), @vtA DATETIME2(7);

BEGIN TRANSACTION;

    -- ══ BƯỚC KIỂM TRA: đếm trên một KHOẢNG dòng ══
    -- Câu COUNT không giữ khóa khoảng (range lock) ở mức READ COMMITTED,
    -- nên sau khi đếm xong, khoảng dữ liệu này hoàn toàn để ngỏ cho phiên
    -- khác chèn dòng mới vào.
    SELECT @soMaA = COUNT(*)
    FROM   dbo.DiscountCode
    WHERE  PromotionID = @PromotionID;

    SELECT 'A' AS Phien, 'Dem duoc' AS Buoc, @soMaA AS SoMa,
           CASE WHEN @soMaA < 2 THEN 'Con cho -> SE THEM MA'
                ELSE 'Du 2 ma -> dung lai' END AS QuyetDinh;

    -- Khoảng hở giữa ĐẾM và CHÈN. Phiên B chen vào đúng lúc này.
    WAITFOR DELAY '00:00:12';

    -- ══ BƯỚC THỰC THI: chèn dựa trên số đếm đã cũ ══
    IF @soMaA < 2
    BEGIN
        SELECT @vfA = StartDatetime, @vtA = EndDatetime
        FROM   dbo.Promotion WHERE PromotionID = @PromotionID;

        INSERT INTO dbo.DiscountCode
            (PromotionID, CodeValue, CodeStatus, ValidFromDatetime, ValidToDatetime,
             GlobalUsageLimit, PerCustomerUsageLimit, ReservedUsageCount, ConsumedUsageCount)
        VALUES (@PromotionID, 'PHANTOM-A', 'Active', @vfA, @vtA, NULL, NULL, 0, 0);

        SELECT 'A' AS Phien, 'Da them ma PHANTOM-A' AS Buoc, 'THANH CONG' AS KetQua;
    END

    -- Đếm lại lần nữa — con số giờ đã khác, dòng "bóng ma" của B đã hiện ra.
    SELECT 'A' AS Phien, 'Dem lai sau khi them' AS Buoc,
           (SELECT COUNT(*) FROM dbo.DiscountCode WHERE PromotionID = @PromotionID) AS SoMa;

COMMIT TRANSACTION;
GO


/* ██████████████████  PHIÊN B — nhân viên thứ hai  ██████████████████
   TRONG LÚC PHIÊN A ĐANG CHỜ.
   ─────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @PromotionID INT = (SELECT PromotionID FROM dbo.Promotion WHERE PromotionName = N'DEMO Loi 4 - Phantom Read');
DECLARE @soMaB INT, @vfB DATETIME2(7), @vtB DATETIME2(7);

-- B cũng đếm, cũng thấy con số cũ như A, cũng kết luận "còn chỗ".
SELECT @soMaB = COUNT(*) FROM dbo.DiscountCode WHERE PromotionID = @PromotionID;

SELECT 'B' AS Phien, 'Dem duoc' AS Buoc, @soMaB AS SoMa;

SELECT @vfB = StartDatetime, @vtB = EndDatetime
FROM   dbo.Promotion WHERE PromotionID = @PromotionID;

INSERT INTO dbo.DiscountCode
    (PromotionID, CodeValue, CodeStatus, ValidFromDatetime, ValidToDatetime,
     GlobalUsageLimit, PerCustomerUsageLimit, ReservedUsageCount, ConsumedUsageCount)
VALUES (@PromotionID, 'PHANTOM-B', 'Active', @vfB, @vtB, NULL, NULL, 0, 0);

SELECT 'B' AS Phien, 'Da them ma PHANTOM-B + COMMIT' AS Buoc,
       (SELECT COUNT(*) FROM dbo.DiscountCode WHERE PromotionID = @PromotionID) AS SoMaHienTai;
GO


/* ██████████████████  KIỂM CHỨNG  ██████████████████ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @PromotionID INT = (SELECT PromotionID FROM dbo.Promotion WHERE PromotionName = N'DEMO Loi 4 - Phantom Read');

SELECT COUNT(*) AS SoMaThucTe,
       2        AS QuyDinhToiDa,
       CASE WHEN COUNT(*) > 2
            THEN '<<< PHANTOM READ: vuot quy dinh ' + CAST(COUNT(*) - 2 AS VARCHAR(2)) + ' ma'
            ELSE 'Khong xay ra (hai phien khong chay chong nhau)'
       END      AS KetLuan
FROM   dbo.DiscountCode WHERE PromotionID = @PromotionID;

SELECT DiscountCodeID AS ID, CodeValue AS Ma, CodeStatus AS TrangThai
FROM   dbo.DiscountCode WHERE PromotionID = @PromotionID
ORDER  BY DiscountCodeID;
GO


/* ── CÁCH KHẮC PHỤC ────────────────────────────────────────────────────────

   Cách 1 — Khóa cả KHOẢNG dữ liệu khi đếm:

       SELECT @soMa = COUNT(*)
       FROM   dbo.DiscountCode WITH (UPDLOCK, HOLDLOCK)
       WHERE  PromotionID = @PromotionID;

   HOLDLOCK ở mức khoảng sẽ tạo range lock, chặn mọi lệnh INSERT vào khoảng
   PromotionID = @PromotionID cho tới khi giao tác kết thúc. Phiên B sẽ phải chờ.

   Cách 2 — Nâng mức cô lập lên SERIALIZABLE cho riêng giao tác này:

       SET TRANSACTION ISOLATION LEVEL SERIALIZABLE;

   Đây là mức duy nhất trong bốn mức chuẩn ANSI chặn được phantom read.

   Cách 3 (bền nhất) — Đưa quy định vào chính database thay vì để ở tầng phần
   mềm, ví dụ một trigger AFTER INSERT đếm lại và ném lỗi nếu vượt 2 mã. Khi
   đó dù tầng ứng dụng kiểm tra sai thì database vẫn là hàng rào cuối cùng.
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  DỌN DẸP  ██████████████████ */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @PromotionID INT = (SELECT PromotionID FROM dbo.Promotion WHERE PromotionName = N'DEMO Loi 4 - Phantom Read');
DELETE FROM dbo.DiscountCode WHERE PromotionID = @PromotionID;
DELETE FROM dbo.Promotion WHERE PromotionID = @PromotionID;
GO
