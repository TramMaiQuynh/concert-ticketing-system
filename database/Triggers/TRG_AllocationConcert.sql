CREATE OR ALTER TRIGGER TRG_AllocationConcert ON BookingEventSeatAllocation
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM inserted i
        JOIN Booking b ON i.BookingID = b.BookingID
        JOIN EventSeat es ON i.EventSeatID = es.EventSeatID
        WHERE b.ConcertID <> es.ConcertID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50000, 'DR-10/CI03 Violation: EventSeat của Allocation phải thuộc cùng Concert với Booking.', 1;
    END
END;
GO
