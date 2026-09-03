-- ============================================================
-- TRG_WaitlistEntryAllocationConcert (CI06)
-- Dam bao EventSeat duoc phan bo phai cung Concert 
-- voi Waitlist cua WaitlistEntry, va phai thuoc dung
-- TicketCategory ma WaitlistEntry do da dang ky.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_WaitlistEntryAllocationConcert
ON WaitlistEntryEventSeatAllocation
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(WaitlistEntryID) AND NOT UPDATE(EventSeatID) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   dbo.WaitlistEntry we ON we.WaitlistEntryID = i.WaitlistEntryID
        JOIN   dbo.Waitlist w ON w.WaitlistID = we.WaitlistID
        JOIN   dbo.EventSeat es ON es.EventSeatID = i.EventSeatID
        WHERE  es.ConcertID <> w.ConcertID
           OR  es.TicketCategoryID <> we.TicketCategoryID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50017, 'CI06 Violation: EventSeat phai thuoc cung Concert va cung TicketCategory ma WaitlistEntry da dang ky.', 1;
    END
END;
GO
