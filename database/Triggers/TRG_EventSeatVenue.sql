-- ============================================================
-- TRG_EventSeatVenue (DR-07)
-- Dam bao Seat duoc tham chieu boi EventSeat phai thuoc
-- chinh Venue ma Concert su dung (BR07).
-- Kiem tra khi INSERT/UPDATE EventSeat vao inventory Concert:
--   - INSERT: mot EventSeat moi phai dung Seat/Venue cua Concert.
--   - UPDATE: neu EventSeat bi doi ConcertID hoac SeatID sang doi
--     tuong khac, cac gia tri moi phai giu dinh Venue nhat quan.
-- Chieu nguoc lai (doi VenueID cua Concert/Seat) duoc bao ve boi
-- TRG_ConcertVenueChangeGuard va TRG_SeatVenueChangeGuard.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_EventSeatVenue
ON EventSeat
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM   inserted  es
        JOIN   Concert   c  ON c.ConcertID  = es.ConcertID
        JOIN   Seat      s  ON s.SeatID     = es.SeatID
        WHERE  s.VenueID <> c.VenueID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50020, 'DR-07/BR07 Violation: Seat cua EventSeat phai thuoc Venue cua Concert.', 1;
    END
END;
GO