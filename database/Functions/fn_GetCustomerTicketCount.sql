-- ============================================================
-- fn_GetCustomerTicketCount
-- Dem tong so ve (Pending + Confirmed) cua mot Customer
-- cho mot Concert cu the.
-- Dung de kiem tra Purchase Limit (BR20, BR21, FR19)
-- trong sp_CreateBooking.
-- Tra ve: INT - so luong EventSeat dang duoc giu/mua.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_GetCustomerTicketCount
(
    @CustomerUserID INT,
    @ConcertID      INT
)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
(
    SELECT ISNULL(COUNT(besa.EventSeatID), 0) AS TicketCount
    FROM   dbo.Booking b
    JOIN   dbo.BookingEventSeatAllocation besa
               ON besa.BookingID = b.BookingID
              AND besa.AllocationStatus = 'Active'
    WHERE  b.CustomerUserID = @CustomerUserID
      AND  b.ConcertID      = @ConcertID
      AND  b.BookingStatus  IN ('Pending', 'Confirmed')
);
GO
