-- ============================================================
-- CreateDBUsers.sql
-- Tao 4 SQL Server Logins va Database Users tuong ung
-- voi 4 vai tro trong he thong Concert Ticketing.
-- Ap dung nguyen tac Least Privilege (S20 / §23.7).
-- ============================================================

-- Luu y: Thay 'YourStrongPassword!' bang mat khau thuc te
--        truoc khi chay script nay trong moi truong san xuat.

-- --- Login & User: app_admin ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_admin')
    CREATE LOGIN app_admin WITH PASSWORD = 'Admin@Concert2026!';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_admin')
    CREATE USER app_admin FOR LOGIN app_admin;

-- --- Login & User: app_organizer ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_organizer')
    CREATE LOGIN app_organizer WITH PASSWORD = 'Organizer@Concert2026!';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_organizer')
    CREATE USER app_organizer FOR LOGIN app_organizer;

-- --- Login & User: app_customer ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_customer')
    CREATE LOGIN app_customer WITH PASSWORD = 'Customer@Concert2026!';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_customer')
    CREATE USER app_customer FOR LOGIN app_customer;

-- --- Login & User: app_checkinstaff ---
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'app_checkinstaff')
    CREATE LOGIN app_checkinstaff WITH PASSWORD = 'Checkin@Concert2026!';

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'app_checkinstaff')
    CREATE USER app_checkinstaff FOR LOGIN app_checkinstaff;

GO
