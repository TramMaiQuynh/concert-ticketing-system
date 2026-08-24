-- ============================================================
-- fn_CalculateBookingSubtotal
-- Tinh tong gia goc = tong SalePrice cua cac EventSeat
-- co Active Allocation trong mot Booking.
-- Dung trong sp_CreateBooking de tinh SubtotalAmount (§12.9.1).
-- Tra ve: DECIMAL(18,0) - tong gia goc.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_CalculateBookingSubtotal
(
    @BookingID INT
)
RETURNS DECIMAL(18,0)
AS
BEGIN
    DECLARE @Subtotal DECIMAL(18,0);

    SELECT @Subtotal = SUM(besa.PriceSnapshot)
    FROM   BookingEventSeatAllocation besa
    WHERE  besa.BookingID        = @BookingID
      AND  besa.AllocationStatus = 'Active';

    RETURN ISNULL(@Subtotal, 0);
END;
GO
