-- ============================================================
-- TRG_TicketConcertConsistency (FK-06)
-- Dam bao hai bat bien denormalization co kiem soat:
--   1. Ticket.ConcertID = Booking.ConcertID cua Booking tuong ung.
--   2. CheckIn.ConcertID = Ticket.ConcertID cua Ticket tuong ung.
-- ============================================================

-- Phan 1: Kiem tra Ticket.ConcertID = Booking.ConcertID
CREATE OR ALTER TRIGGER TRG_TicketConcertConsistency
ON Ticket
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM   inserted t
        JOIN   Booking  b ON b.BookingID = t.BookingID
        WHERE  t.ConcertID <> b.ConcertID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50012, 'FK-06 Violation: Ticket.ConcertID phai bang Booking.ConcertID.', 1;
    END
END;
GO

-- Phan 2: Kiem tra CheckIn.ConcertID = Ticket.ConcertID
CREATE OR ALTER TRIGGER TRG_CheckInConcertConsistency
ON CheckIn
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM   inserted  ci
        JOIN   Ticket    t  ON t.TicketID = ci.TicketID
        WHERE  ci.ConcertID <> t.ConcertID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50013, 'FK-06 Violation: CheckIn.ConcertID phai bang Ticket.ConcertID.', 1;
    END
END;
GO
