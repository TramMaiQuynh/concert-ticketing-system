-- ============================================================
-- TRG_OneActiveTicketPerEventSeat (D18)
-- Dam bao moi EventSeat chi co toi da 1 Ticket co
-- TicketStatus = 'Issued' tai bat ky thoi diem nao.
-- Filtered unique index UIX (EventSeatID) WHERE Issued
-- la bao ve chinh; trigger nay la tang bao ve thu cap.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_OneActiveTicketPerEventSeat
ON Ticket
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT     es.EventSeatID
        FROM       inserted   i
        JOIN       Ticket     t  ON t.EventSeatID = i.EventSeatID
                                AND t.TicketStatus = 'Issued'
                                AND t.TicketID    <> i.TicketID   -- loai chinh no
        JOIN       EventSeat  es ON es.EventSeatID = i.EventSeatID
        WHERE      i.TicketStatus = 'Issued'
        GROUP BY   es.EventSeatID
        HAVING     COUNT(*) >= 1
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50050, 'D18 Violation: Moi EventSeat chi duoc phep co toi da 1 Ticket co trang thai Issued.', 1;
    END
END;
GO
