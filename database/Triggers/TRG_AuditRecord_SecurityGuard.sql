-- ============================================================
-- TRG_AuditRecord_SecurityGuard (CRIT-19)
-- Dam bao rang neu session duoc goi boi app_customer, app_organizer, 
-- hoac app_checkinstaff, thi ActorUserID truyen vao cac SP
-- va ghi vao AuditRecord phai khop voi SESSION_CONTEXT(N'UserID').
-- ============================================================
CREATE OR ALTER TRIGGER dbo.TRG_AuditRecord_SecurityGuard
ON dbo.AuditRecord
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @LoginName NVARCHAR(128) = ORIGINAL_LOGIN();
    
    -- Chi kiem tra voi cac login cua ung dung
    IF @LoginName IN ('app_customer', 'app_organizer', 'app_checkinstaff', 'api_service')
    BEGIN
        DECLARE @SessionUserID INT = CAST(SESSION_CONTEXT(N'UserID') AS INT);
        
        IF @SessionUserID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 50111, 'CRIT-19 Violation: Session Context UserID is not set.', 1;
        END

        IF EXISTS (
            SELECT 1 FROM inserted WHERE ActorUserID <> @SessionUserID
        )
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 50112, 'CRIT-19 Violation: ActorUserID does not match Session Context UserID.', 1;
        END
    END
END;
GO
