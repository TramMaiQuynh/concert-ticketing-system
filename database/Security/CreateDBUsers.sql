-- ============================================================
-- CreateDBUsers.sql
-- Tao 5 SQL Server Login va Database User tuong ung voi 5 vai tro
-- trong he thong Concert Ticketing. Ap dung nguyen tac Least Privilege
-- (S20 / §23.7).
--
-- MAT KHAU KHONG NAM TRONG FILE NAY.
-- Truoc day file nay chua mat khau viet cung cho ca 5 login, va chinh cac
-- mat khau do duoc commit vao repository. Bat ky ai doc duoc ma nguon la dang
-- nhap duoc vao database bang tai khoan api_service - tuc la doc/ghi duoc toan
-- bo du lieu nghiep vu. Mat khau bi mat phai do nguoi trien khai cung cap tai
-- thoi diem trien khai, khong bao gio duoc luu cung ma nguon.
--
-- Mat khau duoc truyen vao qua bien cua sqlcmd (deploy.ps1 dam nhan):
--     sqlcmd ... -v ApiServicePwd="..." AdminPwd="..." ...
--
-- Neu thieu bat ky bien nao, sqlcmd se bao loi va deploy DUNG LAI - dung nhu
-- mong muon: khong duoc phep tao login voi mat khau mac dinh nao do.
-- ============================================================

SET NOCOUNT ON;

-- Bat loi som voi thong bao ro rang thay vi de sqlcmd bao "variable not defined"
-- kem mot doan SQL kho hieu.
IF '$(ApiServicePwd)' = '' OR '$(AdminPwd)' = '' OR '$(OrganizerPwd)' = ''
   OR '$(CustomerPwd)' = '' OR '$(CheckinStaffPwd)' = ''
BEGIN
    RAISERROR('CreateDBUsers.sql: thieu mat khau cho mot hoac nhieu login. Chay qua deploy.ps1 de sinh mat khau tu dong.', 16, 1);
    SET NOEXEC ON;
END
GO

-- --- Login & User: api_service (danh tinh cua backend) ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'api_service')
    CREATE LOGIN api_service WITH PASSWORD = '$(ApiServicePwd)';
ELSE
    ALTER LOGIN api_service WITH PASSWORD = '$(ApiServicePwd)';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'api_service')
    CREATE USER api_service FOR LOGIN api_service;
GO

-- --- Login & User: app_admin ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_admin')
    CREATE LOGIN app_admin WITH PASSWORD = '$(AdminPwd)';
ELSE
    ALTER LOGIN app_admin WITH PASSWORD = '$(AdminPwd)';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_admin')
    CREATE USER app_admin FOR LOGIN app_admin;
GO

-- --- Login & User: app_organizer ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_organizer')
    CREATE LOGIN app_organizer WITH PASSWORD = '$(OrganizerPwd)';
ELSE
    ALTER LOGIN app_organizer WITH PASSWORD = '$(OrganizerPwd)';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_organizer')
    CREATE USER app_organizer FOR LOGIN app_organizer;
GO

-- --- Login & User: app_customer ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_customer')
    CREATE LOGIN app_customer WITH PASSWORD = '$(CustomerPwd)';
ELSE
    ALTER LOGIN app_customer WITH PASSWORD = '$(CustomerPwd)';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_customer')
    CREATE USER app_customer FOR LOGIN app_customer;
GO

-- --- Login & User: app_checkinstaff ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_checkinstaff')
    CREATE LOGIN app_checkinstaff WITH PASSWORD = '$(CheckinStaffPwd)';
ELSE
    ALTER LOGIN app_checkinstaff WITH PASSWORD = '$(CheckinStaffPwd)';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_checkinstaff')
    CREATE USER app_checkinstaff FOR LOGIN app_checkinstaff;
GO

SET NOEXEC OFF;
GO
