-- ============================================================
-- TRG_ConcertVenueChangeGuard (DR-07, bo sung - A1/B1)
-- Bat bien: moi EventSeat cua Concert phai tham chieu Seat thuoc
-- Venue cua Concert (enforce boi TRG_EventSeatVenue). Do do khong
-- duoc doi VenueID cua Concert khi Concert da co EventSeat - cac
-- ghe hien tai thuoc venue cu va se tro thanh khong hop le.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_ConcertVenueChangeGuard
ON Concert
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Chi kiem tra khi cot VenueID thuc su bi thay doi
    IF NOT UPDATE(VenueID) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.ConcertID = i.ConcertID
        WHERE  i.VenueID <> d.VenueID
          AND  EXISTS (SELECT 1 FROM EventSeat es WHERE es.ConcertID = i.ConcertID)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50130, 'DR-07 Violation: Khong the doi VenueID cua Concert khi EventSeat da ton tai.', 1;
    END
END;
GO