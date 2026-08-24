-- ============================================================
-- TRG_SeatVenueConsistency (§14 / BR05)
-- Dam bao bat bien denormalization:
--   Seat.VenueID = Zone.VenueID cua ZoneID tuong ung.
-- Ngan nhap du lieu Seat sai Zone/Venue.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_SeatVenueConsistency
ON Seat
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM   inserted s
        JOIN   Zone     z ON z.ZoneID = s.ZoneID
        WHERE  s.VenueID <> z.VenueID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50120, 'BR05 Violation: Seat.VenueID phai bang Zone.VenueID cua Zone tuong ung.', 1;
    END
END;
GO
