DROP FUNCTION IF EXISTS dbo.fn_CalculateFinalAmount;
GO
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
    SELECT
        CASE
            WHEN (sub.Subtotal - ISNULL(disc.TotalDiscount, 0)) < 0 THEN 0
            ELSE CAST((sub.Subtotal - ISNULL(disc.TotalDiscount, 0)) AS DECIMAL(18,0))
        END AS FinalAmount
    FROM (
        SELECT ISNULL(SUM(PriceSnapshot), 0) AS Subtotal
        FROM dbo.BookingEventSeatAllocation
        WHERE BookingID = @BookingID AND AllocationStatus = 'Active'
    ) sub
    CROSS JOIN (
        SELECT SUM(DiscountAmount) AS TotalDiscount
        FROM dbo.BookingPromotionApplication
        WHERE BookingID = @BookingID
    ) disc
);
GO
