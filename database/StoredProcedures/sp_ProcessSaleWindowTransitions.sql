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
        --
        -- Truoc ban sua nay, dieu kien o day CHI kiem BR10 (co EventSeat) — mot ban
        -- sao doc lap, khong dong bo voi luat StagePass ma sp_UpdateConcertStatus
        -- (duong chuyen trang thai THU CONG) da thi hanh: neu Concert da tao
        -- ConcertMap, phai co revision Locked va MOI EventSeat phai khop voi
        -- ConcertMapRevisionSeat cua revision do. Job dinh ky nay (chuyen trang thai
        -- TU DONG theo gio) bo qua het dieu do — mot Concert co ConcertMap do dang
        -- (chua Lock, hoac Lock nhung con EventSeat le ngoai revision) van tu dong
        -- len OnSale dung luc SaleStartDatetime toi, bo qua chinh rao chan vua duoc
        -- dung cho duong thu cong. Day la mot bai toan batch (nhieu Concert mot luc),
        -- nen khong THROW loi cho ca lo — chi LOC BO Concert khong dat dieu kien
        -- StagePass khoi danh sach chuyen trang thai; Concert do o lai Published,
        -- lan chay ke tiep cua job se thu lai.
        CREATE TABLE #ToOnSale (ConcertID INT NOT NULL);
        INSERT INTO #ToOnSale (ConcertID)
        SELECT c.ConcertID
        FROM Concert c
        WHERE c.ConcertStatus = 'Published'
          AND c.SaleStartDatetime <= @Now
          AND c.SaleEndDatetime IS NOT NULL
          -- Dam bao thoa man BR10: da co EventSeat
          AND EXISTS (SELECT 1 FROM EventSeat WHERE ConcertID = c.ConcertID)
          -- StagePass (neu co dung): phai co revision Locked, va MOI EventSeat cua
          -- Concert phai khop voi ConcertMapRevisionSeat cua dung revision do. Cung
          -- dieu kien voi sp_UpdateConcertStatus, chi khac o day la LOC thay vi THROW.
          AND (
              NOT EXISTS (SELECT 1 FROM ConcertMap cm WHERE cm.ConcertID = c.ConcertID)
              OR EXISTS (
                  SELECT 1
                  FROM ConcertMap cm
                  JOIN ConcertMapRevision cmr ON cmr.ConcertMapID = cm.ConcertMapID AND cmr.RevisionStatus = 'Locked'
                  WHERE cm.ConcertID = c.ConcertID
                    AND NOT EXISTS (
                        SELECT 1
                        FROM EventSeat es
                        WHERE es.ConcertID = c.ConcertID
                          AND NOT EXISTS (
                              SELECT 1
                              FROM ConcertMapRevisionSeat cs
                              JOIN ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID = cs.ConcertMapRevisionSectionID
                              JOIN ConcertMapRevisionFloor   fl  ON fl.ConcertMapRevisionFloorID   = sec.ConcertMapRevisionFloorID
                              WHERE fl.ConcertMapRevisionID = cmr.ConcertMapRevisionID
                                AND cs.EventSeatID = es.EventSeatID
                                AND cs.SeatID = es.SeatID
                          )
                    )
              )
          );

        IF EXISTS (SELECT 1 FROM #ToOnSale)
        BEGIN
            -- OUTPUT chi tra ve cac dong THUC SU duoc cap nhat, nen AuditRecord khong
            -- ghi nham cho Concert bi guard loai bo (trang thai doi dong thoi boi Actor khac).
            DECLARE @ChangedToOnSale TABLE (ConcertID INT NOT NULL);

            UPDATE Concert
            SET ConcertStatus = 'OnSale'
            OUTPUT inserted.ConcertID INTO @ChangedToOnSale(ConcertID)
            WHERE ConcertID IN (SELECT ConcertID FROM #ToOnSale)
              AND ConcertStatus = 'Published';

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
            SELECT @SystemUserID, 'CONCERT_STATUS_CHANGED', 'Concert', CAST(ConcertID AS VARCHAR(64)), 'UPDATE', @Now,
                   '{"ConcertStatus":"Published"}',
                   '{"ConcertStatus":"OnSale", "Reason":"SaleStartDatetime reached"}'
            FROM @ChangedToOnSale;
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
            DECLARE @ChangedToSaleClosed TABLE (ConcertID INT NOT NULL);

            UPDATE Concert
            SET ConcertStatus = 'SaleClosed'
            OUTPUT inserted.ConcertID INTO @ChangedToSaleClosed(ConcertID)
            WHERE ConcertID IN (SELECT ConcertID FROM #ToSaleClosed)
              AND ConcertStatus = 'OnSale';

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
            SELECT @SystemUserID, 'CONCERT_STATUS_CHANGED', 'Concert', CAST(ConcertID AS VARCHAR(64)), 'UPDATE', @Now,
                   '{"ConcertStatus":"OnSale"}',
                   '{"ConcertStatus":"SaleClosed", "Reason":"SaleEndDatetime reached"}'
            FROM @ChangedToSaleClosed;
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
