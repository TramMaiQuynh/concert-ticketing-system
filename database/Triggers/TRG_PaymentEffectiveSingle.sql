-- ============================================================
-- ============================================================
-- TRG_PaymentEffectiveSingle (B2)
-- Dam bao moi Booking chi co toi da mot Payment effective.
-- Song hanh voi filtered unique index UIX_Payment_EffectivePerBooking.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_PaymentEffectiveSingle
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
                    WHERE   p.IsBookingConfirmingPayment = 1
                    GROUP BY p.BookingID
                ) agg
        WHERE   agg.ConfirmedCount > 1
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50070, 'B2 Violation: Moi Booking chi duoc phep co toi da 1 Payment effective.', 1;
    END
END;
GO
