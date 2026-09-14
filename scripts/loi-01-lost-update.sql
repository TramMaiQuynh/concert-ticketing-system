USE ConcertTicketingDB;
GO

/* ╔══════════════════════════════════════════════════════════════════════════╗
   ║  LỖI 1 — LOST UPDATE (Mất mát cập nhật / OVERSELL vé)                     ║
   ╚══════════════════════════════════════════════════════════════════════════╝

   ── TÌNH HUỐNG ────────────────────────────────────────────────────────────
   Đêm nhạc sắp cháy vé. Ghế VIP cuối cùng còn "Available". Khách X mở app
   trên điện thoại, khách Y mở web trên máy tính, CẢ HAI cùng bấm "Giữ ghế"
   cho ĐÚNG ghế đó trong vòng chưa đầy một giây.

   Quy trình giữ ghế (khi KHÔNG có bảo vệ) chỉ đơn giản là ba bước:
       1. Đọc InventoryStatus của ghế -> thấy "Available".
       2. Vì thấy "Available" nên quyết định: được phép giữ.
       3. Ghi InventoryStatus = "OnHold".

   ── TƯƠNG TRANH ────────────────────────────────────────────────────────────
   Cả hai luồng của X và Y đều thực hiện đúng ba bước trên, gần như đồng thời:

       X đọc  -> thấy Available -> quyết định "giữ được"
       Y đọc  -> thấy Available -> quyết định "giữ được"   (X chưa kịp ghi)
       X ghi  -> OnHold, COMMIT
       Y ghi  -> OnHold, COMMIT   (Y không hề biết X đã giữ trước)

   Không ai trong hai luồng NHẬN RA rằng quyết định của mình đã lỗi thời,
   vì READ và WRITE không nằm trong một thao tác nguyên tử được khóa. Đây
   chính xác là LOST UPDATE: bước ghi của X coi như "biến mất" theo nghĩa
   nghiệp vụ — nó bị ghi đè bởi một quyết định (của Y) vốn dựa trên đúng cái
   giá trị cũ mà X đã đọc, không phải dựa trên kết quả X vừa tạo ra.

   ── HẬU QUẢ ───────────────────────────────────────────────────────────────
   Một ghế vật lý duy nhất được xác nhận giữ cho HAI Booking khác nhau
   (oversell). Khi cả hai khách cùng thanh toán thành công, hệ thống phải xử
   lý một trong hai như một sự cố hoàn tiền/bồi thường — điều không thể chấp
   nhận với một ghế đã bán cho người ngồi thật tại chỗ.

   ────────────────────────────────────────────────────────────────────────
   Hệ thống ĐÃ PHÒNG ĐƯỢC lỗi này: dbo.sp_CreateBooking không đọc rồi ghi
   riêng lẻ như trên, mà gộp làm MỘT lệnh UPDATE có điều kiện:

       UPDATE EventSeat SET InventoryStatus = 'OnHold'
       WHERE EventSeatID = @SeatID AND InventoryStatus = 'Available';

   SQL Server tự khóa dòng đang UPDATE cho đến khi transaction kết thúc, nên
   luồng đến sau sẽ thấy điều kiện "InventoryStatus = 'Available'" đã SAI
   (đối thủ vừa đổi nó) và UPDATE của luồng đó khớp 0 dòng — sp_CreateBooking
   phát hiện qua @@ROWCOUNT và trả lỗi "ghế không còn khả dụng" thay vì âm
   thầm xác nhận một ghế đã có chủ.

   Demo dưới đây CỐ Ý bỏ điều kiện đó để cho thấy điều gì XẢY RA nếu thiếu
   nó — đúng những gì sp_CreateBooking phải ngăn chặn.
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  CHUẨN BỊ  ██████████████████
   Không tạo dữ liệu mới — chỉ cần MỘT ghế đang Available của một Concert
   đang OnSale, lấy từ dữ liệu sẵn có trong hệ thống. Cả hai phiên bên dưới
   dùng chung một câu truy vấn xác định (TOP 1 ... ORDER BY EventSeatID)
   nên chắc chắn nhắm vào đúng MỘT ghế giống nhau.
   ────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;

IF NOT EXISTS (
    SELECT 1 FROM dbo.Concert c
    JOIN   dbo.EventSeat es ON es.ConcertID = c.ConcertID
    WHERE  c.ConcertStatus = 'OnSale' AND es.InventoryStatus = 'Available'
)
    THROW 51000, N'Khong tim thay Concert OnSale con EventSeat Available. Can du lieu nay de chay demo.', 1;

SELECT TOP 1
       c.ConcertID, c.ConcertName, es.EventSeatID, es.InventoryStatus AS TrangThaiTruocDemo
FROM   dbo.Concert c
JOIN   dbo.EventSeat es ON es.ConcertID = c.ConcertID
WHERE  c.ConcertStatus = 'OnSale' AND es.InventoryStatus = 'Available'
ORDER  BY es.EventSeatID;
GO


/* ██████████████████  PHIÊN A — khách X (mở web)  ██████████████████ */
SET NOCOUNT ON;
DECLARE @SeatID INT = (
    SELECT TOP 1 es.EventSeatID
    FROM   dbo.EventSeat es
    JOIN   dbo.Concert   c ON c.ConcertID = es.ConcertID
    WHERE  c.ConcertStatus = 'OnSale' AND es.InventoryStatus = 'Available'
    ORDER  BY es.EventSeatID
);
IF @SeatID IS NULL THROW 51000, N'Khong con ghe Available de demo.', 1;

BEGIN TRANSACTION;

    -- Buoc 1: DOC trang thai
    SELECT 'X' AS KhachHang, EventSeatID, InventoryStatus AS DaDoc
    FROM   dbo.EventSeat WHERE EventSeatID = @SeatID;

    -- Khoang ho giua DOC va GHI. Khach Y chen vao dung luc nay.
    WAITFOR DELAY '00:00:06';

    -- Buoc 2+3: QUYET DINH (da thay Available o buoc 1) roi GHI, KHONG kiem
    -- tra lai truoc khi ghi -> day chinh la thieu sot tao ra Lost Update.
    UPDATE dbo.EventSeat SET InventoryStatus = 'OnHold' WHERE EventSeatID = @SeatID;

    SELECT 'X' AS KhachHang, EventSeatID, InventoryStatus AS SauKhiGhi,
           'X tin rang minh vua giu duoc ghe' AS GhiChu
    FROM   dbo.EventSeat WHERE EventSeatID = @SeatID;

COMMIT TRANSACTION;
GO


/* ██████████████████  PHIÊN B — khách Y (mở app di động)  ██████████████████
   CHẠY TRONG LÚC PHIÊN A ĐANG WAITFOR (mở cửa sổ Query thứ hai, chạy ngay).
   ──────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
DECLARE @SeatID INT = (
    SELECT TOP 1 es.EventSeatID
    FROM   dbo.EventSeat es
    JOIN   dbo.Concert   c ON c.ConcertID = es.ConcertID
    WHERE  c.ConcertStatus = 'OnSale' AND es.InventoryStatus = 'Available'
    ORDER  BY es.EventSeatID
);
IF @SeatID IS NULL THROW 51000, N'Khong con ghe Available de demo.', 1;

BEGIN TRANSACTION;

    -- Buoc 1: DOC. Vi X (dang o giua WAITFOR) CHUA COMMIT, Y van doc duoc
    -- Available (dung mac dinh READ COMMITTED — day khong phai dirty read,
    -- vi X chua sua gi ca, chi moi SELECT).
    SELECT 'Y' AS KhachHang, EventSeatID, InventoryStatus AS DaDoc
    FROM   dbo.EventSeat WHERE EventSeatID = @SeatID;

    -- Buoc 2+3: QUYET DINH roi GHI ngay, khong cho, khong kiem tra lai.
    UPDATE dbo.EventSeat SET InventoryStatus = 'OnHold' WHERE EventSeatID = @SeatID;

    SELECT 'Y' AS KhachHang, EventSeatID, InventoryStatus AS SauKhiGhi,
           'Y cung tin rang minh vua giu duoc CUNG ghe do' AS GhiChu
    FROM   dbo.EventSeat WHERE EventSeatID = @SeatID;

COMMIT TRANSACTION;
GO


/* ██████████████████  KIỂM CHỨNG  ██████████████████
   Ca hai phien deu COMMIT thanh cong, khong ai nhan loi. Neu day la hai
   Booking that, ca hai deu se duoc tao ra tren CUNG mot EventSeat -> oversell.
   ──────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
PRINT N'>>> LOST UPDATE: ca X va Y deu COMMIT thanh cong ma khong biet ve nhau.';
PRINT N'>>> Neu day la luong dat ve that, sp_CreateBooking cua CA HAI se doc thay';
PRINT N'>>> InventoryStatus da la OnHold ngay khi ho chuan bi UPDATE — nhung trong';
PRINT N'>>> demo tho nay (khong co dieu kien WHERE), khong ai bi chan lai ca.';
GO


/* ── CÁCH KHẮC PHỤC ────────────────────────────────────────────────────────

   Không dùng "SELECT rồi UPDATE riêng" cho một quyết định giữ tài nguyên
   dùng chung. Phải gộp việc kiểm tra và ghi vào MỘT lệnh UPDATE có điều
   kiện, dựa vào cơ chế khóa dòng tự động của chính lệnh UPDATE đó:

       UPDATE EventSeat
       SET    InventoryStatus = 'OnHold'
       WHERE  EventSeatID = @SeatID AND InventoryStatus = 'Available';

       IF @@ROWCOUNT = 0
           THROW 51004, 'Ghế không còn khả dụng.', 1;

   Đây đúng là cách dbo.sp_CreateBooking của dự án đã làm (kèm thêm AppLock
   theo Customer+Concert để chặn cả trường hợp một khách gửi hai yêu cầu đặt
   vé song song). Khóa chỉ cần giữ trong đúng transaction ngắn ngủi đó, không
   cần nâng mức cô lập toàn hệ thống.
   ────────────────────────────────────────────────────────────────────────── */
