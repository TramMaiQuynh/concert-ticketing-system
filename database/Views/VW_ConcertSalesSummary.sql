-- ============================================================
-- VW_ConcertSalesSummary (BO9 / FR55-FR57)
-- Bao cao doanh thu va ban ve tong hop theo Concert.
-- Cung cap: tong doanh thu, so ve ban, so Booking, ti le huy.
-- ============================================================
CREATE OR ALTER VIEW dbo.VW_ConcertSalesSummary
AS
SELECT
    c.ConcertID,
    c.ConcertName,
    a.ArtistName,
    v.VenueName,
    c.ConcertStatus,
    c.StartDatetime,

    -- Tong so EventSeat trong inventory
    COUNT(DISTINCT es.EventSeatID)                               AS TotalInventorySeats,

    -- So seat dang Available
    SUM(CASE WHEN es.InventoryStatus = 'Available'  THEN 1 ELSE 0 END) AS AvailableSeats,

    -- So seat da ban (Booked)
    SUM(CASE WHEN es.InventoryStatus = 'Booked'     THEN 1 ELSE 0 END) AS BookedSeats,

    -- So seat dang giu (OnHold)
    SUM(CASE WHEN es.InventoryStatus = 'OnHold'
          OR es.InventoryStatus = 'OnHoldForWaitlist' THEN 1 ELSE 0 END) AS OnHoldSeats,

    -- Tong doanh thu tu Payment Confirmed
    ISNULL(SUM(CASE WHEN b.BookingStatus = 'Confirmed'
                    THEN p.Amount END), 0)                       AS TotalRevenue,

    -- Tong so Booking Confirmed
    COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Confirmed'
                        THEN b.BookingID END)                    AS ConfirmedBookings,

    -- Tong so Booking Cancelled
    COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Cancelled'
                        THEN b.BookingID END)                    AS CancelledBookings,

    -- Tong so Booking Expired
    COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Expired'
                        THEN b.BookingID END)                    AS ExpiredBookings

FROM       Concert      c
JOIN       Artist       a   ON a.ArtistID  = c.ArtistID
JOIN       Venue        v   ON v.VenueID   = c.VenueID
LEFT JOIN  EventSeat    es  ON es.ConcertID = c.ConcertID
LEFT JOIN  Booking      b   ON b.ConcertID  = c.ConcertID
LEFT JOIN  Payment      p   ON p.BookingID  = b.BookingID
                            AND p.PaymentStatus = 'Confirmed'
GROUP BY
    c.ConcertID, c.ConcertName, a.ArtistName,
    v.VenueName, c.ConcertStatus, c.StartDatetime;
GO
