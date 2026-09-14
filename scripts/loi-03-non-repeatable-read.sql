USE ConcertTicketingDB;
GO

/* ╔══════════════════════════════════════════════════════════════════════════╗
   ║  LỖI 3 — NON-REPEATABLE READ (Đọc không lặp lại)                         ║
   ╚══════════════════════════════════════════════════════════════════════════╝

   ── TÌNH HUỐNG ────────────────────────────────────────────────────────────
   Khách gọi tổng đài hỏi về đơn đặt vé đang giữ chỗ (Booking Pending) của
   mình. Nhân viên A mở đơn, ĐỌC FinalAmount lần thứ nhất để đọc số tiền cho
   khách nghe qua điện thoại — "Anh/chị cần thanh toán đúng X đồng".

   Cuộc gọi kéo dài vài phút (khách hỏi thêm về ghế, giờ diễn...). Trong lúc
   đó, ở một nơi khác, một giao dịch KHÁC đã CHỈNH SỬA và COMMIT thành công
   một thay đổi hợp lệ trên đúng đơn hàng này (ví dụ: bộ phận vận hành điều
   chỉnh giá theo một quyết định phát sinh).

   Cuối cuộc gọi, nhân viên A dùng CHÍNH giao tác đang mở đó để ĐỌC lại
   FinalAmount lần thứ hai — nhằm tạo yêu cầu thanh toán khớp với con số đã
   đọc ở đầu cuộc gọi.

   ── TƯƠNG TRANH ────────────────────────────────────────────────────────────
   Trong CÙNG MỘT giao tác của A, hai lần đọc trên CÙNG một dòng dữ liệu trả
   về HAI giá trị khác nhau, vì một giao tác khác đã COMMIT xen giữa hai lần
   đọc đó:

       A đọc lần 1  -> FinalAmount = X
       (A đang xử lý cuộc gọi...)
       B sửa + COMMIT -> FinalAmount = X'
       A đọc lần 2  -> FinalAmount = X'   (khác lần 1, CÙNG một giao tác của A)

   Ở mức cô lập mặc định READ COMMITTED, SQL Server CHỈ đảm bảo mỗi lần đọc
   thấy dữ liệu ĐÃ COMMIT tại đúng thời điểm đọc đó — không đảm bảo đọc lại
   một dòng nhiều lần trong cùng giao tác sẽ luôn ra cùng một giá trị. Khóa
   trên dòng đã đọc được nhả ra ngay sau mỗi câu SELECT, nên giao tác khác
   hoàn toàn có thể xen vào giữa hai lần đọc.

   ── HẬU QUẢ ───────────────────────────────────────────────────────────────
   Nhân viên A đã đọc miệng cho khách một con số (X), nhưng phiếu thu được
   tạo ra ở cuối cuộc gọi lại dùng con số khác (X'). Khách thắc mắc vì số
   tiền không khớp với những gì đã được thông báo — không có cách nào xác
   định "con số nào mới là đúng" chỉ bằng cách nhìn vào giao tác của A, vì
   bản thân A đã đọc được cả hai.

   ────────────────────────────────────────────────────────────────────────
   Đây là rủi ro có thật với các đoạn code CHỈ ĐỌC (không dùng UPDLOCK) mà
   đọc lại cùng một dòng nhiều lần trong một giao tác — ví dụ đúng kịch bản
   trên. Các stored procedure GIAO DỊCH chính của dự án (như
   dbo.sp_ConfirmPayment) đã tự khóa Booking bằng WITH (UPDLOCK) ngay từ đầu,
   nên trong LUỒNG THANH TOÁN CHÍNH THỨC, giá trị FinalAmount không thể bị
   một giao tác khác xen vào thay đổi giữa chừng. Rủi ro chỉ còn ở những
   đoạn code tự viết thêm (báo cáo, tư vấn, xem lại) mà không khóa dòng khi
   cần đọc nhiều lần trong cùng một quyết định nghiệp vụ.
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  CHUẨN BỊ  ██████████████████
   Tạo một Booking Pending mới bằng đúng stored procedure thật của dự án
   (dbo.sp_CreateBooking), để có dữ liệu thực và không phụ thuộc BookingID
   cụ thể nào. Cả hai phiên bên dưới cùng lấy Booking Pending MỚI NHẤT
   (ORDER BY BookingID DESC) nên chắc chắn nhắm cùng một đơn.
   ────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @ConcertID INT = (SELECT TOP 1 ConcertID FROM dbo.Concert WHERE ConcertStatus = 'OnSale' ORDER BY ConcertID);
DECLARE @CustomerID INT = (
    SELECT TOP 1 ura.UserID
    FROM   dbo.UserRoleAssignment ura
    JOIN   dbo.Role r ON r.RoleID = ura.RoleID
    WHERE  r.RoleName = 'Customer' AND ura.AssignmentStatus = 'Active'
    ORDER  BY ura.UserID
);
DECLARE @SeatID INT = (
    SELECT TOP 1 es.EventSeatID
    FROM   dbo.EventSeat es
    WHERE  es.ConcertID = @ConcertID AND es.InventoryStatus = 'Available'
    ORDER  BY es.EventSeatID DESC
);
IF @ConcertID IS NULL OR @CustomerID IS NULL OR @SeatID IS NULL
    THROW 53000, N'Can Concert OnSale con ghe Available va it nhat mot Customer de chay demo.', 1;

DECLARE @SeatList NVARCHAR(20) = CAST(@SeatID AS NVARCHAR(20));
DECLARE @NewBookingID INT;
EXEC dbo.sp_CreateBooking
    @CustomerUserID = @CustomerID,
    @ConcertID      = @ConcertID,
    @SeatList       = @SeatList,
    @NewBookingID   = @NewBookingID OUTPUT;

SELECT BookingID, SubtotalAmount, FinalAmount, BookingStatus
FROM   dbo.Booking WHERE BookingID = @NewBookingID;
GO


/* ██████████████████  PHIÊN A — nhân viên tổng đài  ██████████████████ */
SET NOCOUNT ON;
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;

DECLARE @BookingID INT = (SELECT TOP 1 BookingID FROM dbo.Booking WHERE BookingStatus = 'Pending' ORDER BY BookingID DESC);
IF @BookingID IS NULL THROW 53000, N'Khong co Booking Pending de demo — chay lai buoc CHUAN BI.', 1;

BEGIN TRANSACTION;

    SELECT 'A' AS Phien, 'Doc lan 1 - doc mieng cho khach' AS Buoc,
           BookingID, FinalAmount
    FROM   dbo.Booking WHERE BookingID = @BookingID;

    -- Cuoc goi dang dien ra. Trong luc nay B se sua va commit.
    WAITFOR DELAY '00:00:10';

    SELECT 'A' AS Phien, 'Doc lan 2 - dung de tao phieu thu' AS Buoc,
           BookingID, FinalAmount,
           '<<< Khac lan 1 neu B da sua xong - NON-REPEATABLE READ' AS GhiChu
    FROM   dbo.Booking WHERE BookingID = @BookingID;

ROLLBACK TRANSACTION;   -- A chi xem, khong thay doi gi
GO


/* ██████████████████  PHIÊN B — nghiệp vụ khác điều chỉnh giá  ██████████████████
   TRONG LÚC PHIÊN A ĐANG WAITFOR (mở cửa sổ Query thứ hai, chạy ngay).
   ──────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;

DECLARE @BookingID INT = (SELECT TOP 1 BookingID FROM dbo.Booking WHERE BookingStatus = 'Pending' ORDER BY BookingID DESC);
IF @BookingID IS NULL THROW 53000, N'Khong co Booking Pending de demo.', 1;

BEGIN TRANSACTION;
    UPDATE dbo.Booking
    SET    FinalAmount = FinalAmount - 50000
    WHERE  BookingID = @BookingID AND BookingStatus = 'Pending';
COMMIT TRANSACTION;

SELECT 'B' AS Phien, 'Da dieu chinh gia va COMMIT' AS Buoc, BookingID, FinalAmount
FROM   dbo.Booking WHERE BookingID = @BookingID;
GO


/* ── CÁCH KHẮC PHỤC ────────────────────────────────────────────────────────

   Cách 1 — Khóa dòng ngay từ lần đọc đầu tiên nếu sẽ còn đọc/dùng lại giá
   trị đó trong cùng giao tác:

       SELECT FinalAmount FROM Booking WITH (UPDLOCK, HOLDLOCK)
       WHERE  BookingID = @BookingID;

   HOLDLOCK giữ khóa đến hết giao tác, chặn mọi giao tác khác sửa dòng này
   cho tới khi A COMMIT/ROLLBACK — đây đúng là cách dbo.sp_ConfirmPayment
   của dự án đang làm với Booking trước khi tính toán số tiền cuối cùng.

   Cách 2 — Với các luồng chỉ đọc để hiển thị/tư vấn (không có ý định ghi),
   chấp nhận rằng giá trị có thể đổi trước khi giao dịch thật diễn ra, và
   luôn ĐỌC LẠI giá trị mới nhất (khóa) ngay tại thời điểm bắt đầu bước ghi
   thật sự, thay vì tin vào giá trị đã đọc từ trước — nguyên tắc "chốt giá
   ngay trước khi dùng", không phải "dùng lại giá đã đọc từ đầu".
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  DỌN DẸP  ██████████████████
   Hủy Booking demo (vẫn đang Pending, chưa ai thanh toán) để không tồn đọng
   qua các lần chạy — giải phóng lại ghế Available.
   ────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @BookingID INT = (SELECT TOP 1 BookingID FROM dbo.Booking WHERE BookingStatus = 'Pending' ORDER BY BookingID DESC);
IF @BookingID IS NOT NULL
BEGIN
    DECLARE @CustomerID INT = (SELECT CustomerUserID FROM dbo.Booking WHERE BookingID = @BookingID);
    EXEC dbo.sp_CancelBooking @BookingID = @BookingID, @CustomerUserID = @CustomerID;
END
GO
