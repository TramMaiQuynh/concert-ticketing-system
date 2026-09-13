-- ============================================================
-- TRG_TicketCountOnConfirm (B3)
-- Khi BookingStatus chuyen sang 'Confirmed', so Ticket
-- co TicketStatus = 'Issued' phai bang so Allocation
-- co AllocationStatus = 'Active' cua Booking do.
-- Neu lech -> ROLLBACK (ngan phat hanh thieu/thua ve).
--
-- SUA LAI TU BAN DUNG SUBQUERY TUONG QUAN (O(n^2)):
-- Ban truoc dat hai subquery COUNT(*) FROM Ticket/BookingEventSeatAllocation
-- WHERE BookingID = i.BookingID NGAY TRONG dieu kien EXISTS. Voi mot lenh UPDATE
-- set-based doi trang thai NHIEU Booking cung luc (vd. mot tac vu chuyen hang loat
-- Booking hop le sang Confirmed), SQL Server phai danh gia lai HAI subquery do cho
-- TUNG dong cua inserted - va vi Ticket/BookingEventSeatAllocation khong the SEEK
-- hieu qua tu ben trong mot subquery tuong quan tren pseudo-table nhu vay, moi lan
-- danh gia la MOT LAN QUET TOAN BANG. Voi N dong can kiem, ket qua la N lan quet
-- toan bang M dong = O(N*M). Da do thuc nghiem: 500 dong ~0.3s, 1000 dong ~0.9s,
-- 2000 dong ~3.9s, 4000 dong ~15.3s (dung ~x4 moi lan gap doi dau vao - dung chu
-- ky O(n^2)) - ngoai suy 30.000 dong (mot dot huy/het han hang loat Booking cua
-- mot concert lon that su) roi vao khoang 14 PHUT cho DUNG mot cau UPDATE, va voi
-- concert co hang tram nghin ve co the len toi HANG GIO. Anh huong truc tiep
-- sp_ReleaseExpiredHolds (tac vu nen dinh ky) va nhanh huy Concert trong
-- sp_UpdateConcertStatus - ca hai deu doi trang thai NHIEU Booking bang MOT lenh
-- UPDATE set-based, dung nhu chinh binh luan trong TRG_Booking_DiscountUsageGuard
-- da canh bao cho truong hop tuong tu (UPDATE...FROM khop nhieu dong nguon).
--
-- Sua bang GOM NHOM (GROUP BY) MOT LAN DUY NHAT cho ca lo, gioi han dung tap
-- BookingID vua chuyen Confirmed trong lan update nay - dung khuon da duoc kiem
-- chung trong TRG_Booking_DiscountUsageGuard.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_TicketCountOnConfirm
ON Booking
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(BookingStatus) RETURN;

    -- Chi xu ly khi chuyen sang Confirmed
    IF NOT EXISTS (
        SELECT 1 FROM inserted WHERE BookingStatus = 'Confirmed'
    ) RETURN;

    DECLARE @JustConfirmed TABLE (BookingID INT PRIMARY KEY);
    INSERT INTO @JustConfirmed (BookingID)
    SELECT i.BookingID
    FROM   inserted i
    JOIN   deleted  d ON d.BookingID = i.BookingID
    WHERE  i.BookingStatus = 'Confirmed'
      AND  d.BookingStatus <> 'Confirmed';   -- that su la vua chuyen

    IF NOT EXISTS (SELECT 1 FROM @JustConfirmed) RETURN;

    IF EXISTS (
        SELECT jc.BookingID
        FROM   @JustConfirmed jc
        LEFT JOIN (
            SELECT t.BookingID, COUNT(*) AS IssuedCount
            FROM   Ticket t
            JOIN   @JustConfirmed jc2 ON jc2.BookingID = t.BookingID
            WHERE  t.TicketStatus = 'Issued'
            GROUP BY t.BookingID
        ) tk ON tk.BookingID = jc.BookingID
        LEFT JOIN (
            SELECT besa.BookingID, COUNT(*) AS ActiveCount
            FROM   BookingEventSeatAllocation besa
            JOIN   @JustConfirmed jc3 ON jc3.BookingID = besa.BookingID
            WHERE  besa.AllocationStatus = 'Active'
            GROUP BY besa.BookingID
        ) al ON al.BookingID = jc.BookingID
        WHERE  ISNULL(tk.IssuedCount, 0) <> ISNULL(al.ActiveCount, 0)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50040, 'B3 Violation: So Ticket Issued phai bang so Active Allocation khi Booking chuyen sang Confirmed.', 1;
    END
END;
GO
