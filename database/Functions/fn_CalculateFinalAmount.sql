DROP FUNCTION IF EXISTS dbo.fn_CalculateFinalAmount;
GO
-- ============================================================
-- fn_CalculateFinalAmount
-- Tinh FinalAmount = SubtotalAmount - tong DiscountAmount
-- tu tat ca BookingPromotionApplication cua Booking do.
-- FinalAmount >= 0 duoc dam bao boi CHECK constraint tren Booking.
--
-- Subtotal duoc lay tu fn_CalculateBookingSubtotal thay vi tinh lai tai cho:
-- truoc day hai ham cung dinh nghia "tong gia goc cua mot Booking" bang hai doan
-- code song song, nen fn_CalculateBookingSubtotal tro thanh code chet va bat ky
-- thay doi nao ve cach tinh subtotal deu co nguy co chi duoc ap dung o mot noi.
-- Ca hai deu la inline TVF nen SQL Server van noi thang khi toi uu (khong co chi
-- phi goi ham), dong thoi bo sung mot dinh nghia duy nhat cho khai niem nay.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_CalculateFinalAmount
(
    @BookingID INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT
        CASE
            WHEN (sub.Subtotal - ISNULL(disc.TotalDiscount, 0)) < 0 THEN 0
            ELSE CAST((sub.Subtotal - ISNULL(disc.TotalDiscount, 0)) AS DECIMAL(18,0))
        END AS FinalAmount
    FROM dbo.fn_CalculateBookingSubtotal(@BookingID) sub
    CROSS JOIN (
        SELECT SUM(DiscountAmount) AS TotalDiscount
        FROM dbo.BookingPromotionApplication
        WHERE BookingID = @BookingID
    ) disc
);
GO
