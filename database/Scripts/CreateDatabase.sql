-- ============================================================
-- CreateDatabase.sql
-- Tao database (ten do deploy.ps1 truyen vao qua bien sqlcmd $(DbName)) neu
-- chua ton tai. Chay tren master truoc khi deploy cac object khac.
--
-- TRUOC DAY ten database bi VIET CUNG la 'ConcertTicketingDB' trong ca ba cho
-- (CREATE DATABASE, hai PRINT, USE), bat chap deploy.ps1 co tham so -DatabaseName
-- cho phep chon ten khac. He qua: goi deploy.ps1 -DatabaseName "Foo" van tao/dung
-- 'ConcertTicketingDB' o buoc nay, roi PHASE 1 tro di ket noi bang "-d Foo" —
-- database do khong ton tai nen sqlcmd bao loi ngay o buoc xac thuc dang nhap
-- (voi Windows Auth) chu khong phai loi "database khong ton tai" ro rang, rat
-- de bi hieu nham la loi quyen truy cap. Sua bang dung DUNG co che deploy.ps1
-- da dung san cho CreateDBUsers.sql: bien sqlcmd $(...), truyen qua "-v".
-- ============================================================

USE master;
GO

IF NOT EXISTS (
    SELECT 1 FROM sys.databases WHERE name = N'$(DbName)'
)
BEGIN
    CREATE DATABASE [$(DbName)]
        COLLATE Vietnamese_CI_AS;   -- Ho tro ky tu tieng Viet
    PRINT 'Database $(DbName) da duoc tao.';
END
ELSE
BEGIN
    PRINT 'Database $(DbName) da ton tai, bo qua buoc tao.';
END
GO

USE [$(DbName)];
GO
