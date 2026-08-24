-- ============================================================
-- CreateDatabase.sql
-- Tao database ConcertTicketingDB neu chua ton tai.
-- Chay tren master truoc khi deploy cac object khac.
-- ============================================================

USE master;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.databases WHERE name = N'ConcertTicketingDB'
)
BEGIN
    CREATE DATABASE ConcertTicketingDB
        COLLATE Vietnamese_CI_AS;   -- Ho tro ky tu tieng Viet
    PRINT 'Database ConcertTicketingDB da duoc tao.';
END
ELSE
BEGIN
    PRINT 'Database ConcertTicketingDB da ton tai, bo qua buoc tao.';
END
GO

USE ConcertTicketingDB;
GO
