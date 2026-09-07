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

    -- SQL Server kich hoat AFTER trigger MOI LAN CHAY LENH, ke ca khi lenh do
    -- khong tac dong dong nao. Neu khong co guard nay, mot lenh vo hai nhu
    -- `DELETE FROM AuditRecord WHERE AuditID = -1` (khop 0 dong) van ROLLBACK
    -- toan bo transaction dang mo cua caller - mot bay ngam cho moi script
    -- van hanh/bao tri co dinh toi bang nay.
    IF NOT EXISTS (SELECT 1 FROM deleted) AND NOT EXISTS (SELECT 1 FROM inserted)
        RETURN;

    ROLLBACK TRANSACTION;
    THROW 50100, 'BP15/BR50 Violation: AuditRecord la bat bien, khong duoc phep UPDATE hoac DELETE.', 1;
END;
GO
