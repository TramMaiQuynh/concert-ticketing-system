DROP FUNCTION IF EXISTS dbo.fn_CalculateBookingSubtotal;
GO
-- ============================================================
-- fn_CalculateBookingSubtotal
-- Tinh tong gia goc = tong SalePrice cua cac EventSeat
-- co Active Allocation trong mot Booking.
-- Dung trong sp_CreateBooking de tinh SubtotalAmount (§12.9.1).
-- Tra ve: DECIMAL(18,0) - tong gia goc.
-- ============================================================
CREATE FUNCTION dbo.fn_CalculateBookingSubtotal
(
    @BookingID INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN (
    SELECT ISNULL(SUM(besa.PriceSnapshot), 0) AS Subtotal
    FROM   dbo.BookingEventSeatAllocation besa
    WHERE  besa.BookingID        = @BookingID
      AND  besa.AllocationStatus = 'Active'
);
GO
