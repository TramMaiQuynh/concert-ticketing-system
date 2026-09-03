-- ============================================================
-- sp_ProcessSaleWindowTransitions (SIP5 / BR10)
-- Tien trinh tu dong cap nhat trang thai Concert dua tren
-- thoi gian SaleStartDatetime va SaleEndDatetime.
-- Duoc goi dinh ky boi SQL Agent Job (SIP5).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ProcessSaleWindowTransitions
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID INT;
    SELECT  @SystemUserID = UserID FROM UserAccount WHERE Username = 'system';

    DECLARE @Now DATETIME2(7) = SYSDATETIME();

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Published -> OnSale
        -- Dieu kien: SaleStartDatetime <= NOW, SaleEndDatetime > NOW (hoac NULL)
        CREATE TABLE #ToOnSale (ConcertID INT NOT NULL);
        INSERT INTO #ToOnSale (ConcertID)
        SELECT ConcertID
        FROM Concert
        WHERE ConcertStatus = 'Published'
          AND SaleStartDatetime <= @Now
          -- Dam bao thoa man BR10: da co EventSeat
          AND EXISTS (SELECT 1 FROM EventSeat WHERE ConcertID = Concert.ConcertID);

        IF EXISTS (SELECT 1 FROM #ToOnSale)
        BEGIN
            UPDATE Concert
            SET ConcertStatus = 'OnSale'
            WHERE ConcertID IN (SELECT ConcertID FROM #ToOnSale);

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
            SELECT @SystemUserID, 'CONCERT_STATUS_CHANGED', 'Concert', CAST(ConcertID AS VARCHAR(64)), 'UPDATE', @Now,
                   '{"ConcertStatus":"Published"}',
                   '{"ConcertStatus":"OnSale", "Reason":"SaleStartDatetime reached"}'
            FROM #ToOnSale;
        END

        -- 2. OnSale -> SaleClosed
        -- Dieu kien: SaleEndDatetime <= NOW
        CREATE TABLE #ToSaleClosed (ConcertID INT NOT NULL);
        INSERT INTO #ToSaleClosed (ConcertID)
        SELECT ConcertID
        FROM Concert
        WHERE ConcertStatus = 'OnSale'
          AND SaleEndDatetime <= @Now;

        IF EXISTS (SELECT 1 FROM #ToSaleClosed)
        BEGIN
            UPDATE Concert
            SET ConcertStatus = 'SaleClosed'
            WHERE ConcertID IN (SELECT ConcertID FROM #ToSaleClosed);

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
            SELECT @SystemUserID, 'CONCERT_STATUS_CHANGED', 'Concert', CAST(ConcertID AS VARCHAR(64)), 'UPDATE', @Now,
                   '{"ConcertStatus":"OnSale"}',
                   '{"ConcertStatus":"SaleClosed", "Reason":"SaleEndDatetime reached"}'
            FROM #ToSaleClosed;
        END

        DROP TABLE #ToOnSale;
        DROP TABLE #ToSaleClosed;

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#ToOnSale') IS NOT NULL DROP TABLE #ToOnSale;
        IF OBJECT_ID('tempdb..#ToSaleClosed') IS NOT NULL DROP TABLE #ToSaleClosed;
        THROW;
    END CATCH
END;
GO
