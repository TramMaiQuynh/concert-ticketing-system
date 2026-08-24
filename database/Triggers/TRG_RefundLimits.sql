-- ============================================================
-- TRG_RefundLimits (CT-06)
-- Dam bao tong RefundAmount cua tat ca Refund thuoc
-- cung mot Payment khong vuot qua Payment.Amount.
-- Ngan tao them Refund khi Payment da duoc hoan du.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_RefundLimits
ON Refund
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT  r_agg.PaymentID
        FROM    inserted i
        JOIN    (
                    SELECT  r.PaymentID,
                            SUM(r.RefundAmount) AS TotalRefunded
                    FROM    Refund r
                    WHERE   r.RefundStatus NOT IN ('Failed', 'Cancelled')
                    GROUP BY r.PaymentID
                ) r_agg ON r_agg.PaymentID = i.PaymentID
        JOIN    Payment p ON p.PaymentID = i.PaymentID
        WHERE   r_agg.TotalRefunded > p.Amount
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50060, 'CT-06 Violation: Tong RefundAmount vuot qua Payment.Amount.', 1;
    END
END;
GO
