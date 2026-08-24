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
RETURNS INT
AS
BEGIN
    DECLARE @TicketCount INT;

    SELECT @TicketCount = COUNT(besa.EventSeatID)
    FROM   Booking                    b
    JOIN   BookingEventSeatAllocation besa
               ON besa.BookingID = b.BookingID
              AND besa.AllocationStatus = 'Active'
    WHERE  b.CustomerUserID = @CustomerUserID
      AND  b.ConcertID      = @ConcertID
      AND  b.BookingStatus  IN ('Pending', 'Confirmed');

    RETURN ISNULL(@TicketCount, 0);
END;
GO
