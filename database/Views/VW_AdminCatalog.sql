-- Administrative read models. Identity comes exclusively from the authenticated
-- connection's SESSION_CONTEXT, never from query parameters.
-- Venue/Zone/Seat are shared physical catalogues, not concert-owned resources.
CREATE OR ALTER VIEW dbo.VW_AdminConcerts
AS
SELECT c.ConcertID, c.ConcertName, c.VenueID, c.ConcertStatus
FROM dbo.Concert c
WHERE EXISTS (
    SELECT 1 FROM dbo.UserRoleAssignment ura
    JOIN dbo.Role r ON r.RoleID = ura.RoleID
    JOIN dbo.UserAccount u ON u.UserID = ura.UserID
    WHERE ura.UserID = TRY_CAST(SESSION_CONTEXT(N'UserID') AS INT)
      AND u.AccountStatus = 'Active'
      AND ura.AssignmentStatus = 'Active'
      AND (r.RoleName = 'Admin'
           OR (r.RoleName = 'Organizer' AND c.OrganizerUserID = ura.UserID))
);
GO

CREATE OR ALTER VIEW dbo.VW_AdminCategories
AS
SELECT t.TicketCategoryID, c.ConcertID, c.ConcertName,
       t.CategoryName, t.CategoryDescription, t.BasePrice, t.CategoryStatus
FROM dbo.TicketCategory t
JOIN dbo.VW_AdminConcerts c ON c.ConcertID = t.ConcertID;
GO

CREATE OR ALTER VIEW dbo.VW_AdminPromotions
AS
SELECT p.PromotionID, c.ConcertID, c.ConcertName,
       p.PromotionName, p.PromotionDescription, p.PromotionStatus,
       p.DiscountType, p.DiscountValue, p.StartDatetime, p.EndDatetime, p.CodeRequiredFlag
FROM dbo.Promotion p
JOIN dbo.VW_AdminConcerts c ON c.ConcertID = p.ConcertID;
GO

CREATE OR ALTER VIEW dbo.VW_AdminDiscountCodes
AS
SELECT d.DiscountCodeID, p.PromotionID, p.ConcertID, p.ConcertName, p.PromotionName,
       d.CodeValue, d.CodeStatus, d.ValidFromDatetime, d.ValidToDatetime,
       d.GlobalUsageLimit, d.PerCustomerUsageLimit, d.ReservedUsageCount, d.ConsumedUsageCount
FROM dbo.DiscountCode d
JOIN dbo.VW_AdminPromotions p ON p.PromotionID = d.PromotionID;
GO

CREATE OR ALTER VIEW dbo.VW_AdminRefunds
AS
SELECT r.RefundID, r.PaymentID, b.BookingID, c.ConcertID, c.ConcertName,
       r.RefundAmount, r.RefundStatus, r.RefundReason,
       r.RefundRequestTimestamp, r.RefundConfirmationTimestamp
FROM dbo.Refund r
JOIN dbo.Payment p ON p.PaymentID = r.PaymentID
JOIN dbo.Booking b ON b.BookingID = p.BookingID
JOIN dbo.VW_AdminConcerts c ON c.ConcertID = b.ConcertID;
GO
