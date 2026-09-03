-- ============================================================
-- TRG_EventSeatPriceConsistency (BR10a)
-- Khi BasePrice cua TicketCategory thay doi, cascade 
-- gia moi sang SalePrice cua toan bo EventSeat thuoc
-- category do, cung Concert.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_EventSeatPriceConsistency
ON TicketCategory
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(BasePrice) RETURN;

    -- Update toan bo EventSeat thuoc category do thanh BasePrice moi
    UPDATE es
    SET    es.SalePrice = i.BasePrice
    FROM   dbo.EventSeat es
    JOIN   inserted i ON es.TicketCategoryID = i.TicketCategoryID
    JOIN   deleted d ON d.TicketCategoryID = i.TicketCategoryID
    WHERE  i.BasePrice <> d.BasePrice;
END;
GO
