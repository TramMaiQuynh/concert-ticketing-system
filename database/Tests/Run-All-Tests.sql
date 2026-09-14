-- ============================================================
-- Run-All-Tests.sql
-- Master file: chay toan bo test suite va in bao cao.
-- Chay bang: sqlcmd -S .\SQLEXPRESS -E -d ConcertTicketingDB -i Run-All-Tests.sql
--
-- PHAI dat thu muc lam viec o chinh thu muc Tests\ truoc khi chay.
-- sqlcmd phan giai cac chi thi :r theo THU MUC HIEN HANH, khong theo vi tri cua file
-- master nay; chay tu thu muc khac se bao "Invalid filename" cho tung file con roi
-- that bai o buoc doc #TestResults.
--     cd database\Tests
--     sqlcmd -S .\SQLEXPRESS -E -d ConcertTicketingDB -i Run-All-Tests.sql -I
-- Hoac dung Run-All-Tests.ps1 (tu doi thu muc, gop file, va chay them test dong thoi).
--
-- DATABASE DICH DO THAM SO -d QUYET DINH, khong do file nay. Cac file test da bo
-- moi lenh `USE ConcertTicketingDB` (truoc day co 24 cho nam rai rac trong 24 file).
-- Truoc khi bo, -Database cua Run-All-Tests.ps1 bi VO HIEU: tro sang mot database
-- khac thi bo test van ghi vao ConcertTicketingDB, tuc la pha dung cai database
-- nguoi chay dang muon bao ve.
--
-- CANH BAO: bo test nay THAY THE TOAN BO DU LIEU CUA DATABASE DICH.
-- 01_SetupMockData.sql xoa het tai khoan ngoai 'system' o dau moi lan chay, vi
-- 12_Test_SP_AdminAndCatalog.sql yeu cau he thong co DUNG MOT Admin Active (cac
-- test 58406 "Admin cuoi cung" chi xac dinh duoc khi khong con Admin that nao khac).
-- Hay chay tren database kiem thu RIENG; ban .ps1 cung ten co san guard chan truoc.
-- ============================================================
-- CANH BAO: danh sach :r duoi day duoc GO TAY, nen no KHONG tu biet khi co file
-- test moi. Truoc day no dung lai o 13_ va toan bo 8 file StagePass (15_..22_,
-- 124 test case) im lang khong duoc chay — chay file nay van in ra
-- "PASS 226 / FAIL 0", mot ket qua XANH NHUNG THIEU 124 test. Ban .ps1 cung ten
-- da sua dung loi nay bang cach SUY RA danh sach tu thu muc (khop ^\d{2}_.*\.sql),
-- va comment o do ghi ro lich su nay.
--
-- Vi vay: neu ban them mot file NN_*.sql moi, PHAI them mot dong :r o duoi day,
-- hoac chay Run-All-Tests.ps1 (khuyen dung) — no tu phat hien va con chay them
-- hai bai kiem dong thoi (11_Test_Concurrency.ps1, 14_Test_VenueMap_Concurrency.ps1).
:r 00_TestFramework.sql
:r 01_SetupMockData.sql
:r 02_Test_Tables_Constraints.sql
:r 03_Test_Triggers_StateMachine.sql
:r 04_Test_Triggers_Integrity.sql
:r 05_Test_Functions.sql
:r 06_Test_Views.sql
:r 07_Test_SP_CreateBooking.sql
:r 08_Test_SP_ConfirmPayment.sql
:r 09_Test_SP_Others.sql
:r 10_Test_Security_Permissions.sql
:r 11_Test_Concurrency.sql
:r 12_Test_SP_AdminAndCatalog.sql
:r 13_Test_Regression_Fixes.sql
-- StagePass (15_..22_): da tung bi bo sot o day — xem canh bao ngay tren.
:r 15_Test_StagePass_Schema.sql
:r 16_Test_StagePass_TemplateLifecycle.sql
:r 17_Test_StagePass_Geometry.sql
:r 18_Test_StagePass_TemplateGeometrySP.sql
:r 19_Test_StagePass_ConcertMapSP.sql
:r 20_Test_StagePass_TemplateCrud.sql
:r 21_Test_StagePass_AddEventSeatsFromMapRevision.sql
:r 22_Test_Regression_SessionFixes.sql

-- Final Report
GO
GO
PRINT '';
PRINT '================================================';
PRINT ' FINAL TEST REPORT';
PRINT '================================================';

SELECT
    CASE Status WHEN 'PASS' THEN '[PASS]' ELSE '[FAIL]' END AS Mark,
    TestSuite,
    TestName,
    ExpectedBehavior,
    LEFT(ActualMessage,120) AS ActualMessage
FROM #TestResults
ORDER BY TestSuite, TestID;

DECLARE @Total INT = (SELECT COUNT(*) FROM #TestResults);
DECLARE @Pass  INT = (SELECT COUNT(*) FROM #TestResults WHERE Status='PASS');
DECLARE @Fail  INT = (SELECT COUNT(*) FROM #TestResults WHERE Status='FAIL');

PRINT '';
PRINT 'Total : ' + CAST(@Total AS VARCHAR);
PRINT 'PASS  : ' + CAST(@Pass  AS VARCHAR);
PRINT 'FAIL  : ' + CAST(@Fail  AS VARCHAR);

IF @Fail > 0
BEGIN
    PRINT '';
    PRINT 'FAILED TESTS:';
    SELECT TestSuite+'.'+TestName AS Test, ActualMessage
    FROM #TestResults WHERE Status='FAIL';
END
GO

-- ============================================================
-- DON DU LIEU MOCK — dua database ve trang thai sau deploy.
--
-- PHAI nam CUOI CUNG: file nay xoa het du lieu nghiep vu, nen moi test phai chay
-- xong truoc do. No KHONG khop ^\d{2}_ nen khong bao gio bi Run-All-Tests.ps1 gop
-- vao master file — o ban .ps1 do, no duoc goi TUONG MINH sau hai bai kiem dong thoi
-- (11_Test_Concurrency.ps1 can du lieu mock con nguyen).
-- ============================================================
:r Teardown-MockData.sql


