-- ============================================================
-- TRG_PromotionValidity (PI04 / CT-17)
-- Dam bao AppliedTimestamp nam trong khoang hieu luc cua Promotion.
-- Dam bao DiscountCode (neu co) con hieu luc tai thoi diem ap dung.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_PromotionValidity
ON BookingPromotionApplication
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- Kiem tra Promotion con hieu luc tai AppliedTimestamp
    IF EXISTS (
        SELECT 1
        FROM   inserted   bpa
        JOIN   Promotion  p   ON p.PromotionID = bpa.PromotionID
        WHERE  bpa.AppliedTimestamp < p.StartDatetime
           OR  bpa.AppliedTimestamp > p.EndDatetime
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50090, 'PI04/CT-17 Violation: AppliedTimestamp nam ngoai khoang hieu luc cua Promotion.', 1;
    END

    -- Kiem tra DiscountCode con hieu luc (neu co)
    IF EXISTS (
        SELECT 1
        FROM   inserted     bpa
        JOIN   DiscountCode dc ON dc.DiscountCodeID = bpa.DiscountCodeID
        WHERE  bpa.DiscountCodeID IS NOT NULL
          AND  (
                   (dc.ValidFromDatetime IS NOT NULL AND bpa.AppliedTimestamp < dc.ValidFromDatetime)
                OR (dc.ValidToDatetime   IS NOT NULL AND bpa.AppliedTimestamp > dc.ValidToDatetime)
                OR dc.CodeStatus <> 'Active'
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50091, 'CT-17 Violation: DiscountCode het hieu luc hoac khong o trang thai Active.', 1;
    END
END;
GO
