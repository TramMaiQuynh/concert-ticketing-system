-- ============================================================
-- TRG_SystemActorGuard (D14)
-- Dam bao: khi AuditRecord duoc tao boi tien trinh tu dong
-- (SIP1, SIP2, SIP3), ActorUserID phai la tai khoan 'system'
-- (tai khoan du tru khong co Role, PasswordHash = NULL).
-- Nhan biet su kien he thong qua EventType bat dau bang 'SYSTEM_'.
-- ============================================================
CREATE OR ALTER TRIGGER TRG_SystemActorGuard
ON AuditRecord
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID INT;
    SELECT  @SystemUserID = UserID
    FROM    UserAccount
    WHERE   Username = 'system';

    -- Neu EventType bat dau bang 'SYSTEM_' thi ActorUserID phai la system
    IF EXISTS (
        SELECT 1
        FROM   inserted
        WHERE  EventType LIKE 'SYSTEM_%'
          AND  ActorUserID <> @SystemUserID
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50110, 'D14 Violation: Su kien he thong (SIP1-SIP3) phai ghi ActorUserID = tai khoan system.', 1;
    END
END;
GO
