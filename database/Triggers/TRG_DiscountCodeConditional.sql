-- ============================================================
-- TRG_DiscountCodeConditional (FK-03)
-- Neu Promotion.CodeRequiredFlag = 1 thi
-- BookingPromotionApplication.DiscountCodeID PHAI co gia tri (NOT NULL).
-- Dam bao rang buoc dieu kien FK-03.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_DiscountCodeConditional
ON BookingPromotionApplication
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM   inserted   bpa
        JOIN   Promotion  p   ON p.PromotionID = bpa.PromotionID
        WHERE  p.CodeRequiredFlag = 1
          AND  bpa.DiscountCodeID IS NULL
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50080, 'FK-03 Violation: Promotion yeu cau Discount Code nhung DiscountCodeID la NULL.', 1;
    END
END;
GO
