USE ConcertTicketingDB;
GO

/* ╔══════════════════════════════════════════════════════════════════════════╗
   ║  LỖI 5 — DEADLOCK (Khóa chéo / Bế tắc)                                   ║
   ╚══════════════════════════════════════════════════════════════════════════╝

   ── TÌNH HUỐNG ────────────────────────────────────────────────────────────
   Một đơn đặt vé (Booking) đang giữ chỗ, đã có một giao dịch thanh toán
   (Payment) ở trạng thái Pending. Hai luồng nghiệp vụ KHÁC NHAU cùng chạy
   trên đúng cặp Booking/Payment này gần như đồng thời:

       Luồng A — "Xác nhận thanh toán": theo thói quen viết code, đọc/khóa
       Booking trước (để kiểm tra còn Pending không), rồi mới đọc/khóa Payment
       (để cập nhật trạng thái).

       Luồng B — "Đối soát/hủy do quá hạn": lại đọc/khóa Payment trước (để
       kiểm tra Payment có còn Pending không), rồi mới đọc/khóa Booking (để
       cập nhật trạng thái Booking tương ứng).

   Hai đoạn code được viết bởi hai người, ở hai thời điểm khác nhau, không ai
   thống nhất với ai về THỨ TỰ khóa tài nguyên.

   ── TƯƠNG TRANH ────────────────────────────────────────────────────────────
       A khóa Booking            B khóa Payment
       A chờ...                  B chờ...
       A muốn khóa Payment  -->  ĐANG BỊ B GIỮ
       B muốn khóa Booking  -->  ĐANG BỊ A GIỮ

   A đang chờ B nhả Payment. B đang chờ A nhả Booking. Không ai có thể tiến
   thêm được nữa — đây là VÒNG CHỜ VÒNG TRÒN (circular wait), điều kiện bắt
   buộc để có deadlock. SQL Server có một luồng nền (deadlock monitor) định
   kỳ quét đồ thị chờ-khóa; khi phát hiện vòng tròn này, nó CHỌN MỘT trong
   hai giao tác làm "nạn nhân" (deadlock victim), tự ROLLBACK giao tác đó và
   trả về lỗi 1205, để giao tác còn lại được tiếp tục.

   ── HẬU QUẢ ───────────────────────────────────────────────────────────────
   Một trong hai luồng nghiệp vụ (không biết trước là luồng nào) bị hủy bỏ
   giữa chừng với một lỗi hệ thống khó hiểu đối với người dùng cuối. Nếu ứng
   dụng không có logic tự động thử lại (retry) cho đúng loại lỗi 1205, đây
   trở thành một lỗi ngẫu nhiên, không tái lập ổn định, rất khó gỡ khi vào
   sản xuất — vì nó chỉ xảy ra khi hai luồng cụ thể trùng thời điểm.

   ────────────────────────────────────────────────────────────────────────
   Hệ thống PHÒNG lỗi này bằng quy ước: mọi stored procedure chạm tới cả
   Booking lẫn Payment/Refund đều phải lấy khóa theo ĐÚNG MỘT thứ tự cố định
   (Booking trước, rồi mới tới Payment/Refund) — ví dụ dbo.sp_ConfirmPayment
   luôn khóa Payment rồi Booking theo cùng một trình tự nội bộ nhất quán ở
   mọi lần gọi, nên hai lần gọi CÙNG một stored procedure không bao giờ tự
   tạo vòng chờ ngược chiều với chính nó. Deadlock chỉ có thể phát sinh nếu
   MỘT đoạn code MỚI được viết thêm mà không tuân theo đúng quy ước thứ tự
   khóa đó — đúng như luồng B trong demo dưới đây minh họa.
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  CHUẨN BỊ  ██████████████████
   Tạo một Booking Pending kèm Payment Pending mới bằng đúng các stored
   procedure thật của dự án (sp_CreateBooking + sp_InitiatePayment), để có
   dữ liệu thực và không phụ thuộc ID cụ thể nào có sẵn. Cả hai phiên bên
   dưới cùng lấy Booking có Payment Pending MỚI NHẤT.
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
    ORDER  BY es.EventSeatID
);
IF @ConcertID IS NULL OR @CustomerID IS NULL OR @SeatID IS NULL
    THROW 55000, N'Can Concert OnSale con ghe Available va it nhat mot Customer de chay demo.', 1;

DECLARE @SeatList NVARCHAR(20) = CAST(@SeatID AS NVARCHAR(20));
DECLARE @NewBookingID INT;
EXEC dbo.sp_CreateBooking
    @CustomerUserID = @CustomerID,
    @ConcertID      = @ConcertID,
    @SeatList       = @SeatList,
    @NewBookingID   = @NewBookingID OUTPUT;

DECLARE @NewPaymentID INT, @Ref VARCHAR(64), @Amt DECIMAL(18,0);
EXEC dbo.sp_InitiatePayment
    @BookingID        = @NewBookingID,
    @CustomerUserID   = @CustomerID,
    @NewPaymentID     = @NewPaymentID OUTPUT,
    @PaymentReference = @Ref OUTPUT,
    @Amount           = @Amt OUTPUT;

SELECT @NewBookingID AS BookingID, @NewPaymentID AS PaymentID, 'Pending/Pending' AS TrangThai;
GO


/* ██████████████████  PHIÊN A — luồng "Xác nhận thanh toán" (khóa Booking -> Payment)  ██████████████████ */
SET NOCOUNT ON;
DECLARE @BookingID INT = (
    SELECT TOP 1 b.BookingID
    FROM   dbo.Booking b JOIN dbo.Payment p ON p.BookingID = b.BookingID
    WHERE  p.PaymentStatus = 'Pending'
    ORDER  BY b.BookingID DESC
);
IF @BookingID IS NULL THROW 55001, N'Khong co Booking Pending co Payment Pending — chay lai buoc CHUAN BI.', 1;
DECLARE @PaymentID INT = (SELECT TOP 1 PaymentID FROM dbo.Payment WHERE BookingID = @BookingID AND PaymentStatus = 'Pending');

BEGIN TRANSACTION;

    SELECT 'A' AS Luong, 'Khoa Booking' AS Buoc, BookingID, BookingStatus
    FROM   dbo.Booking WITH (UPDLOCK) WHERE BookingID = @BookingID;

    -- Giu khoa Booking, cho mot chut de B kip khoa Payment truoc.
    WAITFOR DELAY '00:00:05';

    -- Muon khoa tiep Payment -> se bi B chan (B dang giu Payment).
    SELECT 'A' AS Luong, 'Khoa Payment' AS Buoc, PaymentID, PaymentStatus
    FROM   dbo.Payment WITH (UPDLOCK) WHERE PaymentID = @PaymentID;

COMMIT TRANSACTION;
GO


/* ██████████████████  PHIÊN B — luồng "Đối soát/hủy quá hạn" (khóa Payment -> Booking)  ██████████████████
   TRONG LÚC PHIÊN A ĐANG WAITFOR (mở cửa sổ Query thứ hai, chạy ngay).
   ──────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
DECLARE @BookingID INT = (
    SELECT TOP 1 b.BookingID
    FROM   dbo.Booking b JOIN dbo.Payment p ON p.BookingID = b.BookingID
    WHERE  p.PaymentStatus = 'Pending'
    ORDER  BY b.BookingID DESC
);
IF @BookingID IS NULL THROW 55001, N'Khong co Booking Pending co Payment Pending.', 1;
DECLARE @PaymentID INT = (SELECT TOP 1 PaymentID FROM dbo.Payment WHERE BookingID = @BookingID AND PaymentStatus = 'Pending');

BEGIN TRANSACTION;

    SELECT 'B' AS Luong, 'Khoa Payment' AS Buoc, PaymentID, PaymentStatus
    FROM   dbo.Payment WITH (UPDLOCK) WHERE PaymentID = @PaymentID;

    WAITFOR DELAY '00:00:05';

    -- Muon khoa tiep Booking -> A dang giu Booking va muon Payment cua B ->
    -- VONG CHO VONG TRON. SQL Server se chon mot ben lam deadlock victim.
    SELECT 'B' AS Luong, 'Khoa Booking' AS Buoc, BookingID, BookingStatus
    FROM   dbo.Booking WITH (UPDLOCK) WHERE BookingID = @BookingID;

COMMIT TRANSACTION;
GO


/* ── KIỂM CHỨNG ────────────────────────────────────────────────────────────
   Một trong hai cửa sổ (A hoặc B) sẽ nhận lỗi:
       Msg 1205: Transaction was deadlocked on lock resources with another
       process and has been chosen as the deadlock victim.
   Cửa sổ còn lại hoàn tất bình thường. Đây CHÍNH LÀ bằng chứng deadlock thật
   sự đã xảy ra (không phải suy luận) — quan sát trực tiếp trên cửa sổ Query.
   ──────────────────────────────────────────────────────────────────────── */


/* ── CÁCH KHẮC PHỤC ────────────────────────────────────────────────────────

   Cách duy nhất triệt để: MỌI đoạn code chạm tới cả hai bảng Booking và
   Payment/Refund phải lấy khóa theo ĐÚNG MỘT thứ tự thống nhất trong toàn
   hệ thống — ví dụ luôn Booking trước, Payment sau — không có ngoại lệ, kể
   cả với các luồng "phụ" như đối soát hay hủy quá hạn tưởng chừng ít quan
   trọng. Một đoạn code duy nhất đi ngược thứ tự là đủ để tạo deadlock với
   MỌI đoạn code khác đang giữ đúng thứ tự.

   Biện pháp bổ trợ (không thay thế được việc thống nhất thứ tự khóa):
     - Giữ giao tác càng ngắn càng tốt, để giảm khoảng thời gian còn giữ khóa.
     - Ứng dụng nên coi lỗi 1205 là loại lỗi "thử lại được" (transient) và tự
       động retry giao tác đã bị chọn làm nạn nhân, thay vì trả lỗi ngay cho
       người dùng.
   ────────────────────────────────────────────────────────────────────────── */


/* ██████████████████  DỌN DẸP  ██████████████████
   Hủy Booking demo (nếu vẫn còn Pending) để không tồn đọng qua các lần chạy.
   ────────────────────────────────────────────────────────────────────── */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
DECLARE @BookingID INT = (
    SELECT TOP 1 b.BookingID
    FROM   dbo.Booking b JOIN dbo.Payment p ON p.BookingID = b.BookingID
    WHERE  p.PaymentStatus = 'Pending'
    ORDER  BY b.BookingID DESC
);
IF @BookingID IS NOT NULL
BEGIN
    DECLARE @CustomerID INT = (SELECT CustomerUserID FROM dbo.Booking WHERE BookingID = @BookingID);
    EXEC dbo.sp_CancelBooking @BookingID = @BookingID, @CustomerUserID = @CustomerID;
END
GO
