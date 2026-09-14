-- ============================================================
-- TRG_ConcertVenueChangeGuard (DR-07, bo sung - A1/B1)
-- Hai bat bien, ca hai chi thi hanh duoc SAU khi UPDATE da xay ra (doc duoc
-- EventSeat/ConcertMap hien tai trong cung transaction voi cac dong moi/cu):
--
-- 1. Moi EventSeat cua Concert phai tham chieu Seat thuoc Venue cua Concert
--    (enforce boi TRG_EventSeatVenue). Do do khong duoc doi VenueID cua Concert
--    khi Concert da co EventSeat - cac ghe hien tai thuoc venue cu va se tro
--    thanh khong hop le.
-- 2. Moi ConcertMapRevision (snapshot StagePass) duoc chup tu VenueTemplate
--    CUA VENUE CU. Doi VenueID cua Concert sau khi da tao ConcertMap — du CHUA
--    co EventSeat nao — lam Section/Seat cua snapshot do khong con khop dia
--    diem that cua Concert nua.
--
-- sp_UpdateConcert.sql da kiem tra ca hai dieu nay SOM (loi 58028 cho nhanh 2)
-- de tra ve thong bao ro rang; trigger nay la lop phong thu chieu sau chan
-- ca duong ghi truc tiep bo qua SP (app_admin co full DML tren schema).
-- ============================================================
CREATE OR ALTER TRIGGER TRG_ConcertVenueChangeGuard
ON Concert
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Chi kiem tra khi cot VenueID thuc su bi thay doi
    IF NOT UPDATE(VenueID) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.ConcertID = i.ConcertID
        WHERE  i.VenueID <> d.VenueID
          AND  EXISTS (SELECT 1 FROM EventSeat es WHERE es.ConcertID = i.ConcertID)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50130, 'DR-07 Violation: Khong the doi VenueID cua Concert khi EventSeat da ton tai.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.ConcertID = i.ConcertID
        WHERE  i.VenueID <> d.VenueID
          AND  EXISTS (SELECT 1 FROM ConcertMap cm WHERE cm.ConcertID = i.ConcertID)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50132, 'DR-07 Violation: Khong the doi VenueID cua Concert khi ConcertMap (StagePass) da ton tai.', 1;
    END
END;
GO