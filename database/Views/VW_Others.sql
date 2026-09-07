-- VW_ActiveInventoryStatus: Trang thai ton kho theo thoi gian thuc
-- Ton kho la thong tin cong khai voi nguoi mua (so do ghe), nen KHONG loc theo
-- Organizer - khac voi cac view bao cao doanh thu/danh sach nguoi dung ben duoi.
CREATE OR ALTER VIEW dbo.VW_ActiveInventoryStatus AS
SELECT es.EventSeatID, es.ConcertID, c.ConcertName, es.InventoryStatus,
       z.ZoneName, s.SeatCode, s.SeatLabel, tc.CategoryName, es.SalePrice,
       es.AddedTimestamp
FROM   EventSeat es
JOIN   Concert  c  ON c.ConcertID  = es.ConcertID
JOIN   Seat     s  ON s.SeatID     = es.SeatID
JOIN   Zone     z  ON z.ZoneID     = s.ZoneID
JOIN   TicketCategory tc ON tc.TicketCategoryID = es.TicketCategoryID AND tc.ConcertID = es.ConcertID
WHERE  c.ConcertStatus <> 'Cancelled';   -- BR50c: Concert da huy khong vao luong ban ve moi
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
-- Noi theo Payment HIEU LUC cua Booking (IsBookingConfirmingPayment = 1) thay vi
-- theo PaymentStatus: chi co toi da MOT Payment hieu luc moi Booking - bao dam boi
-- UIX_Payment_EffectivePerBooking - nen phep noi khong the nhan doi so dong va lam
-- sai SeatCount. Loc theo PaymentStatus khong co bao dam do o muc lugc do.
LEFT JOIN Payment   p    ON p.BookingID  = b.BookingID AND p.IsBookingConfirmingPayment = 1
WHERE  b.CustomerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT) -- RLS: Chi xem duoc dat ve cua chinh minh
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
WHERE  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT);
GO

-- VW_OrganizerPayment: Xem thanh toan thuoc cac Concert ma minh to chuc
CREATE OR ALTER VIEW dbo.VW_OrganizerPayment AS
SELECT p.*
FROM   Payment p
JOIN   Booking b ON b.BookingID = p.BookingID
JOIN   Concert c ON c.ConcertID = b.ConcertID
WHERE  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT);
GO

-- VW_OrganizerTicket: Xem ve thuoc cac Concert ma minh to chuc
CREATE OR ALTER VIEW dbo.VW_OrganizerTicket AS
SELECT t.*
FROM   Ticket t
JOIN   Concert c ON c.ConcertID = t.ConcertID
WHERE  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT);
GO

-- VW_ActivePromotions: Danh sach Promotion hieu luc, KHONG lo DiscountCode
-- Loc theo CA HAI dieu kien: trang thai Active VA thoi diem hien tai nam trong
-- khoang hieu luc nua mo [StartDatetime, EndDatetime) - dung ngu nghia PI04.
-- Neu chi loc theo status, Customer se thay Promotion da het han roi bi
-- sp_ApplyPromotion tu choi bang THROW 54006.
CREATE OR ALTER VIEW dbo.VW_ActivePromotions AS
SELECT p.PromotionID, p.ConcertID, p.PromotionName, p.PromotionDescription,
       p.DiscountType, p.DiscountValue, p.StartDatetime, p.EndDatetime, p.CodeRequiredFlag,
       p.MaxApplicableQuantity, p.MaxDiscountAmount
FROM   Promotion p
WHERE  p.PromotionStatus = 'Active'
  AND  SYSDATETIME() >= p.StartDatetime
  AND  SYSDATETIME() <  p.EndDatetime;
GO

-- VW_CheckInStaffUserAccount: Thong tin nguoi dung an toan cho Check-in Staff
-- (an PasswordHash - day la muc dich goc cua view, thay cho quyen doc bang UserAccount).
--
-- Bo sung gioi han pham vi: truoc day view tra ve TOAN BO UserAccount, nghia la bat ky
-- nhan vien soat ve nao cung doc duoc ho ten + email cua moi nguoi dung trong he thong,
-- ke ca khach cua nhung Concert ho khong duoc phan cong. Dieu do vuot xa nhu cau cong
-- viec va trai voi BR39 (Check-in Staff duoc pham vi hoa theo CheckinStaffAssignment).
-- Nay chi tra ve: chinh minh, va nhung khach co ve thuoc Concert minh duoc phan cong.
-- Admin van thay toan bo.
CREATE OR ALTER VIEW dbo.VW_CheckInStaffUserAccount AS
SELECT ua.UserID, ua.Username, ua.DisplayName, ua.Email, ua.CreatedTimestamp
FROM   UserAccount ua
WHERE  ua.UserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
   OR  EXISTS (SELECT 1
               FROM   dbo.Ticket t
               JOIN   dbo.Booking b ON b.BookingID = t.BookingID
               JOIN   dbo.CheckinStaffAssignment csa
                          ON csa.ConcertID = t.ConcertID
                         AND csa.UserID    = CAST(SESSION_CONTEXT(N'UserID') AS INT)
                         AND csa.AssignmentStatus = 'Active'
               WHERE  b.CustomerUserID = ua.UserID)
   OR  EXISTS (SELECT 1
               FROM   dbo.UserRoleAssignment ura
               JOIN   dbo.Role r ON r.RoleID = ura.RoleID
               WHERE  ura.UserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
                 AND  r.RoleName = 'Admin'
                 AND  ura.AssignmentStatus = 'Active');
GO

-- VW_CheckInReport: Bao cao check-in theo Concert
-- RLS nhu VW_ConcertSalesSummary: Organizer chi thay Concert cua minh, Check-in Staff
-- chi thay Concert duoc phan cong (BR39), Admin thay toan bo. Truoc day view khong loc
-- gi ca trong khi duoc GRANT cho ca app_organizer lan app_checkinstaff.
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
WHERE  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
   OR  EXISTS (SELECT 1 FROM dbo.CheckinStaffAssignment csa
               WHERE csa.ConcertID = c.ConcertID
                 AND csa.UserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
                 AND csa.AssignmentStatus = 'Active')
   OR  EXISTS (SELECT 1 FROM dbo.UserRoleAssignment ura
               JOIN dbo.Role r ON r.RoleID = ura.RoleID
               WHERE ura.UserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
                 AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
GROUP BY c.ConcertID, c.ConcertName, c.StartDatetime;
GO

-- VW_WaitlistQueue: Danh sach cho theo Concert
-- RLS: view nay lo Username/DisplayName cua tung khach hang trong hang cho, nen
-- pham vi phai bam dung chu so huu Concert (BR37); Admin thay toan bo.
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
WHERE  c.OrganizerUserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
   OR  EXISTS (SELECT 1 FROM dbo.UserRoleAssignment ura
               JOIN dbo.Role r ON r.RoleID = ura.RoleID
               WHERE ura.UserID = CAST(SESSION_CONTEXT(N'UserID') AS INT)
                 AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active');
GO

-- VW_AuditTrail: Nhat ky kiem toan toan he thong (chi Admin duoc GRANT - §23.7)
CREATE OR ALTER VIEW dbo.VW_AuditTrail AS
SELECT ar.AuditID, ar.EventTimestamp, ar.EventType, ar.Action,
       ar.EntityType, ar.EntityID,
       ua.UserID AS ActorUserID, ua.Username AS ActorUsername,
       ar.PreviousValue, ar.NewValue, ar.TransactionReference
FROM   AuditRecord  ar
JOIN   UserAccount  ua ON ua.UserID = ar.ActorUserID;
GO
