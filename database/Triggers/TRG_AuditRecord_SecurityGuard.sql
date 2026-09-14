-- ============================================================
-- TRG_AuditRecord_SecurityGuard (CRIT-19)
-- Dam bao rang neu session duoc goi boi app_customer, app_organizer, 
-- hoac app_checkinstaff, thi ActorUserID truyen vao cac SP
-- va ghi vao AuditRecord phai khop voi SESSION_CONTEXT(N'UserID').
-- ============================================================
CREATE OR ALTER TRIGGER TRG_AuditRecord_SecurityGuard
ON dbo.AuditRecord
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @LoginName NVARCHAR(128) = ORIGINAL_LOGIN();
    
    -- Chi kiem tra voi cac login cua ung dung
    -- 'api_service' CO CHU DICH khong nam trong danh sach nay.
    -- Ly do: guard doi MOI lenh INSERT AuditRecord phai co SESSION_CONTEXT(N'UserID').
    -- Tang ung dung da dat dieu do (SqlConnectionFactory goi sp_set_session_context sau
    -- moi lan mo connection), nhung cac loi goi repository TRUC TIEP - integration test,
    -- script van hanh, cong cu quan tri - khong di qua HTTP nen khong co danh tinh de set.
    -- Bat 'api_service' o day se chan toan bo cac loi goi do.
    -- Muon bat: phai cho moi caller truc tiep set session context theo dung ActorUserID
    -- ma no truyen vao SP (neu lech se bi chan boi 50112).
    -- Luu y ve pham vi bao ve: theo UAI04 (§18.11a), authorization la trach nhiem cua
    -- tang application; trigger nay chi la lop gia co tuy chon, khong phai yeu cau bat buoc.
    IF @LoginName IN ('app_customer', 'app_organizer', 'app_checkinstaff')
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
