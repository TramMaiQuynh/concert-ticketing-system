-- ============================================================
-- TRG_WaitlistEntryCategoryConcert (CI05)
-- Dam bao TicketCategory duoc dang ky phai cung Concert 
-- voi Waitlist cua WaitlistEntry.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_WaitlistEntryCategoryConcert
ON WaitlistEntry
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(WaitlistID) AND NOT UPDATE(TicketCategoryID) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   dbo.Waitlist w ON w.WaitlistID = i.WaitlistID
        JOIN   dbo.TicketCategory tc ON tc.TicketCategoryID = i.TicketCategoryID
        WHERE  w.ConcertID <> tc.ConcertID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50016, 'CI05 Violation: TicketCategory phai thuoc cung Concert voi Waitlist.', 1;
    END
END;
GO
