-- ============================================================
-- TRG_TicketCountOnConfirm (B3)
-- Khi BookingStatus chuyen sang 'Confirmed', so Ticket
-- co TicketStatus = 'Issued' phai bang so Allocation
-- co AllocationStatus = 'Active' cua Booking do.
-- Neu lech -> ROLLBACK (ngan phat hanh thieu/thua ve).
-- ============================================================
CREATE OR ALTER TRIGGER TRG_TicketCountOnConfirm
ON Booking
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(BookingStatus) RETURN;

    -- Chi xu ly khi chuyen sang Confirmed
    IF NOT EXISTS (
        SELECT 1 FROM inserted WHERE BookingStatus = 'Confirmed'
    ) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.BookingID = i.BookingID
        WHERE  i.BookingStatus = 'Confirmed'
          AND  d.BookingStatus <> 'Confirmed'   -- that su la vua chuyen
          AND  (
                   -- So Ticket Issued
                   (SELECT COUNT(*) FROM Ticket t
                    WHERE t.BookingID = i.BookingID
                      AND t.TicketStatus = 'Issued')
                   <>
                   -- So Allocation Active
                   (SELECT COUNT(*) FROM BookingEventSeatAllocation besa
                    WHERE besa.BookingID = i.BookingID
                      AND besa.AllocationStatus = 'Active')
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50040, 'B3 Violation: So Ticket Issued phai bang so Active Allocation khi Booking chuyen sang Confirmed.', 1;
    END
END;
GO
