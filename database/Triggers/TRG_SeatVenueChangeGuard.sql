-- ============================================================
-- TRG_SeatVenueChangeGuard (DR-07, bo sung - A1/B1)
-- Bat bien: moi EventSeat tham chieu mot Seat thuoc Venue cua
-- Concert (enforce boi TRG_EventSeatVenue). Do do khong duoc
-- doi VenueID cua Seat khi Seat dang duoc EventSeat tham chieu -
-- neu doi, cac EventSeat do se tham chieu vao ghe sai venue.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_SeatVenueChangeGuard
ON Seat
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Chi kiem tra khi cot VenueID thuc su bi thay doi
    IF NOT UPDATE(VenueID) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.SeatID = i.SeatID
        WHERE  i.VenueID <> d.VenueID
          AND  EXISTS (SELECT 1 FROM EventSeat es WHERE es.SeatID = i.SeatID)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50131, 'DR-07 Violation: Khong the doi VenueID cua Seat khi Seat dang duoc EventSeat tham chieu.', 1;
    END
END;
GO

-- ============================================================
-- Ghim THU TU kich hoat tren Seat UPDATE.
--
-- Bang Seat co HAI trigger AFTER UPDATE va ca hai deu tu choi DUNG mot lenh
-- "doi VenueID cua mot Seat dang duoc EventSeat tham chieu":
--   * TRG_SeatVenueChangeGuard  -> 50131 (khong duoc doi khi con EventSeat tham chieu)
--   * TRG_SeatVenueConsistency  -> 50120 (Seat.VenueID phai bang Zone.VenueID)
-- SQL Server KHONG dam bao thu tu giua cac AFTER trigger cung bang cung hanh dong khi
-- chua ghim; trigger nao chay truoc la tuy y. Hau qua that: cung mot thao tac cua nguoi
-- dung co the tra ve 50131 o lan chay nay va 50120 o lan chay khac - va vi tang API anh
-- xa MA LOI sang ma HTTP, cung mot hanh dong se cho hai phan hoi khac nhau. Loi nay da
-- bieu hien: mot test hoi quy xanh o lan chay nay, do o lan deploy sach ke tiep.
--
-- Ghim guard chay TRUOC vi thong bao cua no moi la cai nguoi van hanh can: no noi RO
-- nguyen nhan (ghe dang nam trong kho ve) va viec phai lam. 50120 chi phat bieu lai bat
-- bien o muc thap hon.
-- Viec ghim thu tu duoc thuc hien tap trung tai Triggers/TRG_FiringOrder.sql (chay
-- cuoi Phase 4). Ly do khong ghim tai day: CREATE OR ALTER TRIGGER RESET thu tu da
-- ghim, nen ghim rai rac trong tung file se bi chinh cac file deploy sau do xoa mat.
-- File tap trung con kiem chung duoc rang moi to hop nhieu trigger deu da co thu tu.