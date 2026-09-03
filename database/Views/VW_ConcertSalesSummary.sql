-- ============================================================
-- VW_ConcertSalesSummary (BO9 / FR55-FR57)
-- Bao cao doanh thu va ban ve tong hop theo Concert.
-- Cung cap: tong doanh thu, so ve ban, so Booking, ti le huy.
--
-- LUU Y (fix loi - A1):
-- Truoc day view dung 3 LEFT JOIN doc lap (EventSeat, Booking, Payment)
-- tren cung ConcertID -> tao phep nhan Cartesian giua cac tuyen doc:
--   - TotalRevenue = SUM(p.Amount) bi nhan len theo so EventSeat cua Concert
--     (vd: 1 booking 2 ghe thanh toan 2 trieu nhung concert co 6 ghe -> bao 12 trieu)
--   - AvailableSeats/BookedSeats/OnHoldSeats cung bi nhan theo so Booking/Payment.
-- Fix: moi chi so duoc tinh RIENG tren bang phu thach cua no bang CROSS APPLY,
-- ket qua khong con bi sai lech boi so dong cua cac bang khac.
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

    -- --- Inventory: tinh tren EventSeat cua Concert ---
    inv.TotalInventorySeats,
    inv.AvailableSeats,
    inv.BookedSeats,
    inv.OnHoldSeats,

    -- --- Doanh thu: tinh tren Payment Confirmed cua Booking Confirmed ---
    (rev.GrossRevenue - ref.TotalRefunds) AS TotalRevenue,

    -- --- So Booking theo trang thai: tinh tren Booking cua Concert ---
    st.ConfirmedBookings,
    st.CancelledBookings,
    st.ExpiredBookings

FROM       Concert c
LEFT JOIN  Artist  a ON a.ArtistID = c.ArtistID
LEFT JOIN  Venue   v ON v.VenueID  = c.VenueID

CROSS APPLY (
    SELECT COUNT(*)                                                          AS TotalInventorySeats,
           SUM(CASE WHEN es.InventoryStatus = 'Available'                THEN 1 ELSE 0 END) AS AvailableSeats,
           SUM(CASE WHEN es.InventoryStatus = 'Booked'                   THEN 1 ELSE 0 END) AS BookedSeats,
           SUM(CASE WHEN es.InventoryStatus IN ('OnHold', 'OnHoldForWaitlist')
                                                                    THEN 1 ELSE 0 END) AS OnHoldSeats
    FROM   dbo.EventSeat es
    WHERE  es.ConcertID = c.ConcertID
      AND  es.IsDeleted = 0
) inv

CROSS APPLY (
    SELECT ISNULL(SUM(p.Amount), 0) AS GrossRevenue
    FROM   dbo.Payment p
    WHERE  p.BookingID IN (SELECT b.BookingID FROM dbo.Booking b WHERE b.ConcertID = c.ConcertID AND b.IsDeleted = 0)
      AND  p.IsBookingConfirmingPayment = 1
      AND  p.PaymentStatus IN ('Confirmed', 'PartiallyRefunded', 'Refunded')
      AND  p.IsDeleted = 0
) rev

CROSS APPLY (
    SELECT ISNULL(SUM(r.RefundAmount), 0) AS TotalRefunds
    FROM   dbo.Refund r
    JOIN   dbo.Payment p ON p.PaymentID = r.PaymentID
    JOIN   dbo.Booking b ON b.BookingID = p.BookingID
    WHERE  b.ConcertID = c.ConcertID
      AND  r.RefundStatus = 'Confirmed'
      AND  p.IsDeleted = 0
      AND  b.IsDeleted = 0
) ref

CROSS APPLY (
    SELECT COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Confirmed' THEN b.BookingID END) AS ConfirmedBookings,
           COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Cancelled' THEN b.BookingID END) AS CancelledBookings,
           COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Expired'  THEN b.BookingID END) AS ExpiredBookings
    FROM   dbo.Booking b
    WHERE  b.ConcertID = c.ConcertID
      AND  b.IsDeleted = 0
) st
WHERE c.IsDeleted = 0;
GO