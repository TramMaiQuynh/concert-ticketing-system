-- VW_ActiveInventoryStatus: Trang thai ton kho theo thoi gian thuc
CREATE OR ALTER VIEW dbo.VW_ActiveInventoryStatus AS
SELECT es.EventSeatID, es.ConcertID, c.ConcertName, es.InventoryStatus,
       z.ZoneName, s.SeatCode, s.SeatLabel, tc.CategoryName, es.SalePrice,
       es.AddedTimestamp
FROM   EventSeat es
JOIN   Concert  c  ON c.ConcertID  = es.ConcertID
JOIN   Seat     s  ON s.SeatID     = es.SeatID
JOIN   Zone     z  ON z.ZoneID     = s.ZoneID
JOIN   TicketCategory tc ON tc.TicketCategoryID = es.TicketCategoryID AND tc.ConcertID = es.ConcertID;
GO

-- VW_CustomerBookingHistory: Lich su dat ve cua Customer
CREATE OR ALTER VIEW dbo.VW_CustomerBookingHistory AS
SELECT b.BookingID, b.CustomerUserID, ua.Username, ua.DisplayName,
       b.ConcertID, c.ConcertName, b.BookingStatus,
       b.HoldStartDatetime, b.HoldExpiryDatetime,
       b.SubtotalAmount, b.FinalAmount,
       b.CreatedTimestamp, b.ConfirmedTimestamp, b.CancelledTimestamp,
       COUNT(besa.EventSeatID) AS SeatCount,
       p.PaymentStatus, p.Amount AS PaidAmount
FROM   Booking      b
JOIN   UserAccount  ua   ON ua.UserID    = b.CustomerUserID
JOIN   Concert      c    ON c.ConcertID  = b.ConcertID
LEFT JOIN BookingEventSeatAllocation besa ON besa.BookingID = b.BookingID
LEFT JOIN Payment   p    ON p.BookingID  = b.BookingID AND p.PaymentStatus = 'Confirmed'
GROUP BY b.BookingID, b.CustomerUserID, ua.Username, ua.DisplayName,
         b.ConcertID, c.ConcertName, b.BookingStatus,
         b.HoldStartDatetime, b.HoldExpiryDatetime,
         b.SubtotalAmount, b.FinalAmount,
         b.CreatedTimestamp, b.ConfirmedTimestamp, b.CancelledTimestamp,
         p.PaymentStatus, p.Amount;
GO

-- VW_CheckInReport: Bao cao check-in theo Concert
CREATE OR ALTER VIEW dbo.VW_CheckInReport AS
SELECT c.ConcertID, c.ConcertName, c.StartDatetime,
       COUNT(DISTINCT t.TicketID)                                       AS TotalIssuedTickets,
       COUNT(DISTINCT ci.CheckInID)                                     AS TotalCheckedIn,
       COUNT(DISTINCT CASE WHEN t.TicketStatus = 'Issued' THEN t.TicketID END) AS PendingEntry,
       CAST(
           CASE WHEN COUNT(DISTINCT t.TicketID) = 0 THEN 0
                ELSE COUNT(DISTINCT ci.CheckInID) * 100.0 / COUNT(DISTINCT t.TicketID)
           END AS DECIMAL(5,2))                                         AS CheckInRatePct
FROM   Concert  c
LEFT JOIN Ticket  t   ON t.ConcertID = c.ConcertID AND t.TicketStatus IN ('Issued','Used')
LEFT JOIN CheckIn ci  ON ci.TicketID = t.TicketID
GROUP BY c.ConcertID, c.ConcertName, c.StartDatetime;
GO

-- VW_WaitlistQueue: Danh sach cho theo Concert
CREATE OR ALTER VIEW dbo.VW_WaitlistQueue AS
SELECT w.WaitlistID, w.ConcertID, c.ConcertName, w.WaitlistStatus, w.AllocationPolicy,
       we.WaitlistEntryID, we.CustomerUserID, ua.Username, ua.DisplayName,
       we.JoinedTimestamp, we.QueuePosition, we.EntryStatus,
       we.OpportunityGrantedTimestamp, we.OpportunityExpiryTimestamp,
       we.ResultingBookingID
FROM   Waitlist      w
JOIN   Concert       c   ON c.ConcertID = w.ConcertID
JOIN   WaitlistEntry we  ON we.WaitlistID = w.WaitlistID
JOIN   UserAccount   ua  ON ua.UserID = we.CustomerUserID;
GO

-- VW_AuditTrail: Nhat ky kiem toan toan he thong
CREATE OR ALTER VIEW dbo.VW_AuditTrail AS
SELECT ar.AuditID, ar.EventTimestamp, ar.EventType, ar.Action,
       ar.EntityType, ar.EntityID,
       ua.UserID AS ActorUserID, ua.Username AS ActorUsername,
       ar.PreviousValue, ar.NewValue, ar.TransactionReference
FROM   AuditRecord  ar
JOIN   UserAccount  ua ON ua.UserID = ar.ActorUserID;
GO
