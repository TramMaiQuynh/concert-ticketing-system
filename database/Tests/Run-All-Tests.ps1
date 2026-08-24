# ====================================================================
# Run-All-Tests.ps1
# Chay toan bo Test Suite va in ra bao cao.
# ====================================================================

param (
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$Database = "ConcertTicketingDB"
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " CONCERT TICKETING DB - AUTOMATED TEST SUITE" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# Gom tat ca cac file test thanh 1 master file de giu session tempdb..#TestResults
$masterFile = "MasterTestRun.sql"
if (Test-Path $masterFile) { Remove-Item $masterFile }

$sqlFiles = @(
    "00_TestFramework.sql",
    "01_SetupMockData.sql",
    "02_Test_Tables_Constraints.sql",
    "03_Test_Triggers_StateMachine.sql",
    "04_Test_Triggers_Integrity.sql",
    "05_Test_Functions.sql",
    "06_Test_Views.sql",
    "07_Test_SP_CreateBooking.sql",
    "08_Test_SP_ConfirmPayment.sql",
    "09_Test_SP_Others.sql",
    "10_Test_Security_Permissions.sql"
)

Write-Host "Compiling test scripts..." -ForegroundColor Yellow
foreach ($file in $sqlFiles) {
    if (Test-Path $file) {
        Get-Content $file | Out-File -Append -Encoding UTF8 $masterFile
    } else {
        Write-Warning "File $file not found!"
    }
}

# Add query to print test results
@"
-- In ra ket qua toan bo
SELECT 
    CASE WHEN Status = 'PASS' THEN '[PASS]' ELSE '[FAIL]' END AS StatusMark,
    TestSuite, 
    TestName, 
    ExpectedBehavior,
    ActualMessage
FROM #TestResults
ORDER BY TestSuite, TestID;

DECLARE @FailCount INT = (SELECT COUNT(*) FROM #TestResults WHERE Status = 'FAIL');
DECLARE @TotalCount INT = (SELECT COUNT(*) FROM #TestResults);
PRINT '------------------------------------------------';
PRINT 'TOTAL TESTS: ' + CAST(@TotalCount AS VARCHAR);
PRINT 'FAILED TESTS: ' + CAST(@FailCount AS VARCHAR);
IF @FailCount > 0
    THROW 50000, 'ONE OR MORE TESTS FAILED!', 1;
"@ | Out-File -Append -Encoding UTF8 $masterFile

Write-Host "Executing SQL test suite..." -ForegroundColor Yellow
$sqlCmdArgs = "-S", $ServerInstance, "-E", "-d", $Database, "-i", $masterFile, "-b"
$process = Start-Process -FilePath "sqlcmd" -ArgumentList $sqlCmdArgs -NoNewWindow -Wait -PassThru

if ($process.ExitCode -eq 0) {
    Write-Host "`n[PASS] All SQL Tests completed successfully!" -ForegroundColor Green
} else {
    Write-Host "`n[FAIL] SQL Tests failed. Please check the output above." -ForegroundColor Red
}

Write-Host "`nRunning Concurrency Test..." -ForegroundColor Yellow
.\11_Test_Concurrency.ps1 -ServerInstance $ServerInstance -Database $Database

Write-Host "`nCleaning up..." -ForegroundColor Yellow
Remove-Item $masterFile

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " TEST RUN COMPLETED" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
