-- ============================================================
-- TRG_AuditLog (BP15)
-- Dam bao AuditRecord la bat bien (immutable):
--   - Chan moi UPDATE va DELETE tren bang AuditRecord.
-- Theo yeu cau BR50 va §12.17: lich su audit khong duoc
-- sua doi hoac xoa sau khi da ghi nhan.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_AuditLog
ON AuditRecord
AFTER UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;

    ROLLBACK TRANSACTION;
    THROW 50100, 'BP15/BR50 Violation: AuditRecord la bat bien, khong duoc phep UPDATE hoac DELETE.', 1;
END;
GO
