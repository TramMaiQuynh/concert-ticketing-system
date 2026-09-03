-- ============================================================
-- TRG_Booking_DiscountUsageGuard (CRIT-15)
-- Quan ly vong doi cua ReservedUsageCount va ConsumedUsageCount 
-- khi trang thai Booking thay doi.
--  - Booking -> Expired/Cancelled: tra lai Reserved (tru di).
--  - Booking -> Confirmed: chuyen Reserved thanh Consumed.
-- ============================================================
CREATE OR ALTER TRIGGER dbo.TRG_Booking_DiscountUsageGuard
ON dbo.Booking
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Neu khong co thay doi BookingStatus thi bo qua
    IF NOT UPDATE(BookingStatus) RETURN;

    -- Lay danh sach cac booking bi huy (Cancelled/Expired) ma TRUOC DO la Pending
    -- va danh sach cac booking thanh cong (Confirmed) ma TRUOC DO la Pending
    -- (Hoac neu tu Confirmed bi Cancelled thi phai tinh Consumed -> Tra lai, nhung 
    -- spec noi khi hoan tien co hoan usage limit khong? Thuong la khong. Nhu vay
    -- Cancelled tu Confirmed co the chua can, nhung tam thoi chung ta se giam Consumed neu can.
    -- Tuy nhien an toan nhat la chi check tu Pending -> Expired/Cancelled (giam Reserved)
    -- va Pending -> Confirmed (Reserved -> Consumed).
    
    DECLARE @StatusChanges TABLE (
        BookingID INT,
        OldStatus VARCHAR(32),
        NewStatus VARCHAR(32)
    );

    INSERT INTO @StatusChanges (BookingID, OldStatus, NewStatus)
    SELECT i.BookingID, d.BookingStatus, i.BookingStatus
    FROM inserted i
    JOIN deleted d ON i.BookingID = d.BookingID
    WHERE i.BookingStatus <> d.BookingStatus;

    IF NOT EXISTS (SELECT 1 FROM @StatusChanges) RETURN;

    -- Xy ly Pending -> Expired hoac Cancelled (Giam Reserved)
    IF EXISTS (SELECT 1 FROM @StatusChanges WHERE OldStatus = 'Pending' AND NewStatus IN ('Expired', 'Cancelled'))
    BEGIN
        UPDATE dc
        SET ReservedUsageCount = dc.ReservedUsageCount - 1
        FROM DiscountCode dc
        JOIN BookingPromotionApplication bpa ON bpa.DiscountCodeID = dc.DiscountCodeID
        JOIN @StatusChanges sc ON sc.BookingID = bpa.BookingID
        WHERE sc.OldStatus = 'Pending' AND sc.NewStatus IN ('Expired', 'Cancelled');
    END

    -- Xy ly Pending -> Confirmed (Giam Reserved, Tang Consumed)
    IF EXISTS (SELECT 1 FROM @StatusChanges WHERE OldStatus = 'Pending' AND NewStatus = 'Confirmed')
    BEGIN
        UPDATE dc
        SET ReservedUsageCount = dc.ReservedUsageCount - 1,
            ConsumedUsageCount = dc.ConsumedUsageCount + 1
        FROM DiscountCode dc
        JOIN BookingPromotionApplication bpa ON bpa.DiscountCodeID = dc.DiscountCodeID
        JOIN @StatusChanges sc ON sc.BookingID = bpa.BookingID
        WHERE sc.OldStatus = 'Pending' AND sc.NewStatus = 'Confirmed';
    END

    -- Xy ly Confirmed -> Cancelled (Neu huy booking da confirm thi tra lai Consumed)
    IF EXISTS (SELECT 1 FROM @StatusChanges WHERE OldStatus = 'Confirmed' AND NewStatus = 'Cancelled')
    BEGIN
        UPDATE dc
        SET ConsumedUsageCount = dc.ConsumedUsageCount - 1
        FROM DiscountCode dc
        JOIN BookingPromotionApplication bpa ON bpa.DiscountCodeID = dc.DiscountCodeID
        JOIN @StatusChanges sc ON sc.BookingID = bpa.BookingID
        WHERE sc.OldStatus = 'Confirmed' AND sc.NewStatus = 'Cancelled';
    END

END;
GO
