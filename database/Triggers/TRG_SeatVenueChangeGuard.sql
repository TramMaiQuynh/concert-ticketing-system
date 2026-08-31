-- ============================================================
-- TRG_SeatVenueChangeGuard (DR-07, bo sung - A1/B1)
-- Bat bien: moi EventSeat tham chieu mot Seat thuoc Venue cua
-- Concert (enforce boi TRG_EventSeatVenue). Do do khong duoc
-- doi VenueID cua Seat khi Seat dang duoc EventSeat tham chieu -
-- neu doi, cac EventSeat do se tham chieu vao ghe sai venue.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_SeatVenueChangeGuard
ON Seat
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Chi kiem tra khi cot VenueID thuc su bi thay doi
    IF NOT UPDATE(VenueID) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.SeatID = i.SeatID
        WHERE  i.VenueID <> d.VenueID
          AND  EXISTS (SELECT 1 FROM EventSeat es WHERE es.SeatID = i.SeatID)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50131, 'DR-07 Violation: Khong the doi VenueID cua Seat khi Seat dang duoc EventSeat tham chieu.', 1;
    END
END;
GO