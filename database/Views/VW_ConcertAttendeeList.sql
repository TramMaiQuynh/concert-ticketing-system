-- ============================================================
-- VW_ConcertAttendeeList (BO9 / FR55-FR56 / BP14)
-- Danh sach nguoi giu tung ve cua mot Concert, phuc vu will-call, ho tro khach
-- mat ve, theo doi no-show — dung "attendee manifest" chuan cua cac nen tang
-- ve lon (Eventbrite/Ticketmaster).
--
-- KHONG tra TicketCode: BP9 chi giao doc ticket_code/QR cho Check-in Staff/Admin
-- tai cong; BP14 (bao cao Organizer) chi noi "ticket usage" - trang thai/dem,
-- khong phai ma tho. Tra them ma tho o day se mo mot kenh ro ri thu hai cho
-- dung loai bearer-credential vua duoc siet o FR31.
--
-- RLS qua SESSION_CONTEXT(N'UserID'), cung khuon VW_ConcertSalesSummary/
-- VW_CheckInReport/VW_WaitlistQueue: Organizer chi thay Concert cua chinh minh,
-- Admin thay toan bo. KHONG lam bang WHERE o tang C# - xem comment trong
-- VW_ConcertSalesSummary.sql ve su co ro ri doanh thu cheo Organizer da tung
-- xay ra khi RLS chi nam o tang ung dung.
-- ============================================================
CREATE OR ALTER VIEW dbo.VW_ConcertAttendeeList AS
SELECT t.TicketID, t.BookingID, t.ConcertID, t.TicketStatus,
       t.IssuedTimestamp, t.UsedTimestamp, t.CancelledTimestamp,
       s.SeatCode, z.ZoneName, tc.CategoryName,
       ua.UserID AS CustomerUserID, ua.Username, ua.DisplayName
FROM   Ticket         t
JOIN   Booking        b  ON b.BookingID  = t.BookingID
JOIN   UserAccount    ua ON ua.UserID    = b.CustomerUserID
JOIN   EventSeat      es ON es.EventSeatID = t.EventSeatID
JOIN   Seat           s  ON s.SeatID     = es.SeatID
JOIN   Zone            z  ON z.ZoneID     = s.ZoneID
JOIN   TicketCategory tc ON tc.TicketCategoryID = es.TicketCategoryID
JOIN   Concert         c  ON c.ConcertID  = t.ConcertID
WHERE  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
   OR  EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
               WHERE ura.UserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
                 AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active');
GO
