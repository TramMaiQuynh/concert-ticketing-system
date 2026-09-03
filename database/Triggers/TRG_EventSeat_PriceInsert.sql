-- ============================================================
-- TRG_EventSeat_PriceInsert (CRIT-17)
-- Dam bao khi INSERT truc tiep vao EventSeat (bypass sp),
-- SalePrice phai bang BasePrice cua TicketCategory.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_EventSeat_PriceInsert
ON EventSeat
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   TicketCategory tc ON tc.TicketCategoryID = i.TicketCategoryID
        WHERE  i.SalePrice <> tc.BasePrice
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50060, 'CRIT-17 Violation: SalePrice cua EventSeat phai bang BasePrice cua TicketCategory khi insert.', 1;
    END
END;
GO
