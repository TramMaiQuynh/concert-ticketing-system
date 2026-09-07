-- ============================================================
-- VW_ConcertSalesSummary (BO9 / FR55-FR57)
-- Bao cao doanh thu va ban ve tong hop theo Concert.
-- Cung cap: doanh thu NET, ton kho, so Booking theo trang thai.
--
-- LUU Y 1 (fix Cartesian - A1):
-- Truoc day view dung 3 LEFT JOIN doc lap (EventSeat, Booking, Payment)
-- tren cung ConcertID -> tao phep nhan Cartesian giua cac tuyen doc.
-- Fix: moi chi so duoc tinh RIENG tren bang phu trach cua no bang CROSS APPLY.
--
-- LUU Y 2 (fix ro ri du lieu giua cac Organizer):
-- Truoc day view KHONG loc theo chu so huu nhung lai duoc GRANT cho app_organizer,
-- nen mot Organizer doc duoc doanh thu, ton kho va so lieu Booking cua MOI Concert
-- cua MOI Organizer khac - vi pham truc tiep BR37 ("Organizer theo
-- Concert.OrganizerUserID"). Ba view VW_OrganizerBooking/Payment/Ticket duoc tao ra
-- dung de chan dieu do tren Booking/Payment/Ticket, nhung bao cao tong hop - noi
-- chua thong tin nhay cam nhat - lai bi bo ngo.
-- Nay ap dung cung mot mau RLS qua SESSION_CONTEXT, kem duong vuot cho Admin
-- (Admin toan he thong theo §23.7).
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

    -- --- Doanh thu NET (BR51a): thu duoc - da hoan THUC SU (Refund Confirmed) ---
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
) inv

CROSS APPLY (
    SELECT ISNULL(SUM(p.Amount), 0) AS GrossRevenue
    FROM   dbo.Payment p
    WHERE  p.BookingID IN (SELECT b.BookingID FROM dbo.Booking b WHERE b.ConcertID = c.ConcertID)
      AND  p.IsBookingConfirmingPayment = 1
      AND  p.PaymentStatus IN ('Confirmed', 'PartiallyRefunded', 'Refunded')
) rev

CROSS APPLY (
    SELECT ISNULL(SUM(r.RefundAmount), 0) AS TotalRefunds
    FROM   dbo.Refund r
    JOIN   dbo.Payment p ON p.PaymentID = r.PaymentID
    JOIN   dbo.Booking b ON b.BookingID = p.BookingID
    WHERE  b.ConcertID = c.ConcertID
      AND  r.RefundStatus = 'Confirmed'
) ref

CROSS APPLY (
    SELECT COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Confirmed' THEN b.BookingID END) AS ConfirmedBookings,
           COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Cancelled' THEN b.BookingID END) AS CancelledBookings,
           COUNT(DISTINCT CASE WHEN b.BookingStatus = 'Expired'  THEN b.BookingID END) AS ExpiredBookings
    FROM   dbo.Booking b
    WHERE  b.ConcertID = c.ConcertID
) st

-- RLS (BR37): Organizer chi thay Concert cua chinh minh; Admin thay toan bo.
WHERE c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
   OR EXISTS (SELECT 1
              FROM   dbo.UserRoleAssignment ura
              JOIN   dbo.Role r ON r.RoleID = ura.RoleID
              WHERE  ura.UserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
                AND  r.RoleName = 'Admin'
                AND  ura.AssignmentStatus = 'Active');
GO
