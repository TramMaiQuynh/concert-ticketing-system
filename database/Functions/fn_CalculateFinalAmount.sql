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
RETURNS DECIMAL(18,0)
AS
BEGIN
    DECLARE @Subtotal      DECIMAL(18,0);
    DECLARE @TotalDiscount DECIMAL(18,0);
    DECLARE @FinalAmount   DECIMAL(18,0);

    SELECT @Subtotal = dbo.fn_CalculateBookingSubtotal(@BookingID);

    SELECT @TotalDiscount = ISNULL(SUM(bpa.DiscountAmount), 0)
    FROM   BookingPromotionApplication bpa
    WHERE  bpa.BookingID = @BookingID;

    SET @FinalAmount = @Subtotal - @TotalDiscount;

    -- Dam bao khong am (du lieu bao ve; CHECK tren Booking se bat neu SP logic sai)
    IF @FinalAmount < 0 SET @FinalAmount = 0;

    RETURN @FinalAmount;
END;
GO
