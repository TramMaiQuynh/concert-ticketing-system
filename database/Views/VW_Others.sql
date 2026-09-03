-- VW_ActiveInventoryStatus: Trang thai ton kho theo thoi gian thuc
CREATE OR ALTER VIEW dbo.VW_ActiveInventoryStatus AS
SELECT es.EventSeatID, es.ConcertID, c.ConcertName, es.InventoryStatus,
       z.ZoneName, s.SeatCode, s.SeatLabel, tc.CategoryName, es.SalePrice,
       es.AddedTimestamp
FROM   EventSeat es
JOIN   Concert  c  ON c.ConcertID  = es.ConcertID
JOIN   Seat     s  ON s.SeatID     = es.SeatID
JOIN   Zone     z  ON z.ZoneID     = s.ZoneID
JOIN   TicketCategory tc ON tc.TicketCategoryID = es.TicketCategoryID AND tc.ConcertID = es.ConcertID
WHERE  es.IsDeleted = 0 AND c.IsDeleted = 0;
GO

-- VW_CustomerBookingHistory: Lich su dat ve cua Customer (co RLS)
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
LEFT JOIN Payment   p    ON p.BookingID  = b.BookingID AND p.PaymentStatus = 'Confirmed' AND p.IsDeleted = 0
WHERE  b.IsDeleted = 0 AND c.IsDeleted = 0
  AND  b.CustomerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT) -- RLS: Chi xem duoc dat ve cua chinh minh
GROUP BY b.BookingID, b.CustomerUserID, ua.Username, ua.DisplayName,
         b.ConcertID, c.ConcertName, b.BookingStatus,
         b.HoldStartDatetime, b.HoldExpiryDatetime,
         b.SubtotalAmount, b.FinalAmount,
         b.CreatedTimestamp, b.ConfirmedTimestamp, b.CancelledTimestamp,
         p.PaymentStatus, p.Amount;
GO

-- VW_OrganizerBooking: Xem dat ve thuoc cac Concert ma minh to chuc
CREATE OR ALTER VIEW dbo.VW_OrganizerBooking AS
SELECT b.* 
FROM   Booking b
JOIN   Concert c ON c.ConcertID = b.ConcertID
JOIN   UserAccount ua ON ua.UserID = c.OrganizerUserID
WHERE  b.IsDeleted = 0 AND c.IsDeleted = 0
  AND  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT);
GO

-- VW_OrganizerPayment: Xem thanh toan thuoc cac Concert ma minh to chuc
CREATE OR ALTER VIEW dbo.VW_OrganizerPayment AS
SELECT p.* 
FROM   Payment p
JOIN   Booking b ON b.BookingID = p.BookingID
JOIN   Concert c ON c.ConcertID = b.ConcertID
JOIN   UserAccount ua ON ua.UserID = c.OrganizerUserID
WHERE  p.IsDeleted = 0 AND b.IsDeleted = 0 AND c.IsDeleted = 0
  AND  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT);
GO

-- VW_OrganizerTicket: Xem ve thuoc cac Concert ma minh to chuc
CREATE OR ALTER VIEW dbo.VW_OrganizerTicket AS
SELECT t.* 
FROM   Ticket t
JOIN   Concert c ON c.ConcertID = t.ConcertID
JOIN   UserAccount ua ON ua.UserID = c.OrganizerUserID
WHERE  t.IsDeleted = 0 AND c.IsDeleted = 0
  AND  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT);
GO

-- VW_ActivePromotions: Danh sach Promotion hieu luc, KHONG lo DiscountCode
CREATE OR ALTER VIEW dbo.VW_ActivePromotions AS
SELECT p.PromotionID, p.ConcertID, p.PromotionName, p.PromotionDescription,
       p.DiscountType, p.DiscountValue, p.StartDatetime, p.EndDatetime, p.CodeRequiredFlag
FROM   Promotion p
WHERE  p.PromotionStatus = 'Active';
GO

-- VW_CheckInStaffUserAccount: Thong tin nguoi dung an toan cho Checkin Staff (an PasswordHash)
CREATE OR ALTER VIEW dbo.VW_CheckInStaffUserAccount AS
SELECT UserID, Username, DisplayName, Email, PhoneNumber, CreatedTimestamp, LastLoginTimestamp, LockoutEnd, FailedAttemptCount
FROM   UserAccount;
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
LEFT JOIN Ticket  t   ON t.ConcertID = c.ConcertID AND t.TicketStatus IN ('Issued','Used') AND t.IsDeleted = 0
LEFT JOIN CheckIn ci  ON ci.TicketID = t.TicketID
WHERE  c.IsDeleted = 0
GROUP BY c.ConcertID, c.ConcertName, c.StartDatetime;
GO

-- VW_WaitlistQueue: Danh sach cho theo Concert
CREATE OR ALTER VIEW dbo.VW_WaitlistQueue AS
SELECT w.WaitlistID, w.ConcertID, c.ConcertName, w.WaitlistStatus, w.AllocationPolicy,
       we.WaitlistEntryID, we.CustomerUserID, ua.Username, ua.DisplayName,
       we.JoinedTimestamp, we.QueuePosition, we.EntryStatus,
       we.TicketCategoryID, tc.CategoryName, we.RequestedQuantity,
       (SELECT COUNT(*) FROM dbo.WaitlistEntryEventSeatAllocation wa WHERE wa.WaitlistEntryID = we.WaitlistEntryID AND wa.AllocationStatus = 'Active') AS ActiveAllocationCount,
       we.OpportunityGrantedTimestamp, we.OpportunityExpiryTimestamp,
       we.ResultingBookingID
FROM   Waitlist      w
JOIN   Concert       c   ON c.ConcertID = w.ConcertID
JOIN   WaitlistEntry we  ON we.WaitlistID = w.WaitlistID
JOIN   UserAccount   ua  ON ua.UserID = we.CustomerUserID
JOIN   TicketCategory tc ON tc.TicketCategoryID = we.TicketCategoryID
WHERE  w.IsDeleted = 0 AND c.IsDeleted = 0 AND we.IsDeleted = 0;
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
