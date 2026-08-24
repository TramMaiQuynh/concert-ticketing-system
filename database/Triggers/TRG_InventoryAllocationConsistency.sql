-- ============================================================
-- TRG_InventoryAllocationConsistency (CONSTR-04)
-- Dam bao: khi co mot Active Allocation cho EventSeat,
-- InventoryStatus cua EventSeat do phai la 'OnHold' hoac 'Booked'.
-- Kiem tra khi INSERT/UPDATE tren BookingEventSeatAllocation.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_InventoryAllocationConsistency
ON BookingEventSeatAllocation
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Chi kiem tra cac Allocation dang Active
    IF EXISTS (
        SELECT 1
        FROM   inserted  i
        JOIN   EventSeat es ON es.EventSeatID = i.EventSeatID
        WHERE  i.AllocationStatus = 'Active'
          AND  es.InventoryStatus NOT IN ('OnHold', 'Booked')
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50030, 'CONSTR-04 Violation: EventSeat voi Active Allocation phai o trang thai OnHold hoac Booked.', 1;
    END
END;
GO
