-- ============================================================
-- fn_CalculateFinalAmount
-- Tinh FinalAmount = SubtotalAmount - tong DiscountAmount
-- tu tat ca BookingPromotionApplication cua Booking do.
-- FinalAmount >= 0 duoc dam bao boi CHECK constraint tren Booking.
-- Tra ve: DECIMAL(18,0) - gia sau khi ap dung tat ca Promotion.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_CalculateFinalAmount
(
    @BookingID INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT CASE
               WHEN (s.Subtotal - d.TotalDiscount) < 0 THEN 0
               ELSE (s.Subtotal - d.TotalDiscount)
           END AS FinalAmount
    FROM   dbo.fn_CalculateBookingSubtotal(@BookingID) s
    CROSS APPLY (
        SELECT ISNULL(SUM(bpa.DiscountAmount), 0) AS TotalDiscount
        FROM   dbo.BookingPromotionApplication bpa
        WHERE  bpa.BookingID = @BookingID
    ) d
);
GO
