-- ============================================================
-- TRG_CMRSeat_EventSeatConsistency (bo sung, cung tinh than DR-07)
--
-- ConcertMapRevisionSeat.sql tu ghi ro bat bien nay CAN TRIGGER nhung chua co:
-- "EventSeat.ConcertID (qua EventSeatID) phai khop Concert cua chinh
-- ConcertMapRevision nay... EventSeat.SeatID phai khop
-- ConcertMapRevisionSeat.SeatID". Truoc ban them nay, bat bien do CHI duoc
-- thi hanh boi sp_AddEventSeatsFromMapRevision (duong ghi DUY NHAT hop le) —
-- mot UPDATE truc tiep tren ConcertMapRevisionSeat.EventSeatID (vd. boi
-- app_admin, dang co full DML tren schema — xem GrantPermissions.sql) co the
-- gan mot EventSeatID sai Concert hoac sai Seat ma khong bi chan o dau ca, lam
-- so do StagePass cong khai tro toi mot hang ton kho khong khop chinh no.
--
-- Cung khuon TRG_EventSeatVenue: kiem tra qua bang inserted, chi khi
-- EventSeatID IS NOT NULL (NULL la trang thai binh thuong cua ghe chua ban).
-- ============================================================
CREATE OR ALTER TRIGGER TRG_CMRSeat_EventSeatConsistency
ON ConcertMapRevisionSeat
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM inserted WHERE EventSeatID IS NOT NULL) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted  cs
        JOIN   ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID = cs.ConcertMapRevisionSectionID
        JOIN   ConcertMapRevisionFloor   fl  ON fl.ConcertMapRevisionFloorID   = sec.ConcertMapRevisionFloorID
        JOIN   ConcertMapRevision        cmr ON cmr.ConcertMapRevisionID      = fl.ConcertMapRevisionID
        JOIN   ConcertMap                cm  ON cm.ConcertMapID              = cmr.ConcertMapID
        JOIN   EventSeat                 es  ON es.EventSeatID               = cs.EventSeatID
        WHERE  cs.EventSeatID IS NOT NULL
          AND  (es.ConcertID <> cm.ConcertID OR es.SeatID <> cs.SeatID)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50140, 'DR-07 Violation: ConcertMapRevisionSeat.EventSeatID phai tro toi mot EventSeat dung Concert cua revision nay va dung SeatID cua chinh dong nay.', 1;
    END
END;
GO
