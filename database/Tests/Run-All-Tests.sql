-- ============================================================
-- Run-All-Tests.sql
-- Master file: chay toan bo test suite va in bao cao.
-- Chay bang: sqlcmd -S .\SQLEXPRESS -E -d ConcertTicketingDB -i Run-All-Tests.sql
-- ============================================================
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

-- Final Report
GO
USE ConcertTicketingDB;
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


