-- ============================================================
-- TRG_PaymentConfirmedSingle (B2)
-- Dam bao moi Booking chi co toi da mot Payment
-- co PaymentStatus = 'Confirmed' tai bat ky thoi diem nao.
-- Song hanh voi filtered unique index UIX_Payment_ConfirmedPerBooking.
-- Trigger nay la tang bao ve thu cap de bao ve khi
-- index bi disable hoac bypass.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_PaymentConfirmedSingle
ON Payment
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT  BookingID
        FROM    (
                    SELECT  p.BookingID,
                            COUNT(*) AS ConfirmedCount
                    FROM    Payment p
                    JOIN    inserted i ON i.BookingID = p.BookingID
                    WHERE   p.PaymentStatus = 'Confirmed'
                    GROUP BY p.BookingID
                ) agg
        WHERE   agg.ConfirmedCount > 1
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50070, 'B2 Violation: Moi Booking chi duoc phep co toi da 1 Payment co trang thai Confirmed.', 1;
    END
END;
GO
