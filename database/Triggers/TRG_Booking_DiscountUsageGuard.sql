-- ============================================================
-- TRG_Booking_DiscountUsageGuard (CRIT-15)
-- Quan ly vong doi cua ReservedUsageCount va ConsumedUsageCount
-- khi trang thai Booking thay doi.
--   - Pending -> Expired/Cancelled : tra lai suat da giu (giam Reserved).
--   - Pending -> Confirmed         : chuyen Reserved thanh Consumed.
--   - Confirmed -> Cancelled       : KHONG tra lai Consumed. Mot ma giam gia
--     da duoc dung de mua hang that su thi coi nhu da tieu thu; neu tra lai,
--     khach co the lap vong dat-huy de xai lai ma khong gioi han.
--
-- CANH BAO TRIEN KHAI (day la loi da tung xay ra o phien ban truoc):
--   KHONG duoc viet dang `UPDATE dc SET c = c - 1 FROM DiscountCode dc JOIN ...`.
--   Trong T-SQL, `UPDATE ... FROM` khi mot dong DICH khop NHIEU dong NGUON chi
--   cap nhat dong dich DUNG MOT LAN (chon dong nguon bat ky, khong xac dinh).
--   sp_ReleaseExpiredHolds va cascade huy Concert deu doi trang thai NHIEU
--   Booking bang MOT lenh UPDATE set-based, nen trigger nay chay mot lan cho ca
--   lo: N booking cung dung mot ma se chi duoc tra lai 1 suat thay vi N.
--   Phan chenh lech ro ri VINH VIEN va se lam ma giam gia bi khoa cung boi
--   CHK_DiscountCode_UsageCounts du chua ai thuc su dung het han muc.
--   => Bat buoc GOM NHOM (GROUP BY) truoc, roi tru theo dung so luong dem duoc.
-- ============================================================
CREATE OR ALTER TRIGGER dbo.TRG_Booking_DiscountUsageGuard
ON dbo.Booking
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(BookingStatus) RETURN;

    DECLARE @StatusChanges TABLE (
        BookingID INT PRIMARY KEY,
        OldStatus VARCHAR(32),
        NewStatus VARCHAR(32)
    );

    INSERT INTO @StatusChanges (BookingID, OldStatus, NewStatus)
    SELECT i.BookingID, d.BookingStatus, i.BookingStatus
    FROM   inserted i
    JOIN   deleted  d ON d.BookingID = i.BookingID
    WHERE  i.BookingStatus <> d.BookingStatus;

    IF NOT EXISTS (SELECT 1 FROM @StatusChanges) RETURN;

    -- Pending -> Expired/Cancelled: nha lai suat da giu.
    UPDATE dc
    SET    dc.ReservedUsageCount = dc.ReservedUsageCount - agg.Cnt
    FROM   dbo.DiscountCode dc
    JOIN   (
               SELECT bpa.DiscountCodeID, COUNT(*) AS Cnt
               FROM   dbo.BookingPromotionApplication bpa
               JOIN   @StatusChanges sc ON sc.BookingID = bpa.BookingID
               WHERE  bpa.DiscountCodeID IS NOT NULL
                 AND  sc.OldStatus = 'Pending'
                 AND  sc.NewStatus IN ('Expired', 'Cancelled')
               GROUP BY bpa.DiscountCodeID
           ) agg ON agg.DiscountCodeID = dc.DiscountCodeID;

    -- Pending -> Confirmed: suat giu tro thanh suat da tieu thu.
    UPDATE dc
    SET    dc.ReservedUsageCount = dc.ReservedUsageCount - agg.Cnt,
           dc.ConsumedUsageCount = dc.ConsumedUsageCount + agg.Cnt
    FROM   dbo.DiscountCode dc
    JOIN   (
               SELECT bpa.DiscountCodeID, COUNT(*) AS Cnt
               FROM   dbo.BookingPromotionApplication bpa
               JOIN   @StatusChanges sc ON sc.BookingID = bpa.BookingID
               WHERE  bpa.DiscountCodeID IS NOT NULL
                 AND  sc.OldStatus = 'Pending'
                 AND  sc.NewStatus = 'Confirmed'
               GROUP BY bpa.DiscountCodeID
           ) agg ON agg.DiscountCodeID = dc.DiscountCodeID;
END;
GO
