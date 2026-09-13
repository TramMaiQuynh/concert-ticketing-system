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

# Danh sach file test duoc SUY RA tu thu muc, KHONG liet ke cung.
# Truoc day danh sach nay duoc go tay va dung lai o 10_Test_Security_Permissions.sql,
# nen moi file test them vao sau do (12_, 13_) im lang khong duoc chay: nguoi chay
# script van thay "All SQL Tests completed successfully" nhung thuc te thieu hang chuc
# test. Quy uoc: moi file khop NN_*.sql (NN la hai chu so) deu duoc nap theo thu tu ten.
# Rieng 11_Test_Concurrency.sql duoc nap trong danh sach nay; ban .ps1 cung ten chay
# rieng o cuoi vi no can nhieu ket noi song song.
$sqlFiles = Get-ChildItem -Path $scriptDir -Filter "*.sql" |
            Where-Object { $_.Name -match '^\d{2}_' } |
            Sort-Object Name |
            Select-Object -ExpandProperty Name

Write-Host ("Phat hien {0} file test: {1}" -f $sqlFiles.Count, ($sqlFiles -join ', ')) -ForegroundColor DarkGray

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
# -I (SET QUOTED_IDENTIFIER ON) la BAT BUOC, khong phai tuy chon:
# 8 bang nghiep vu co filtered index (AuditRecord, Payment, Ticket, QueueEntry,
# WaitlistEntry, BookingEventSeatAllocation, RefreshToken...) va SQL Server tu choi
# moi lenh INSERT/UPDATE ad-hoc len chung khi QUOTED_IDENTIFIER = OFF (loi 1934).
# Hien tai cac file test tu dat SET QUOTED_IDENTIFIER ON nen van chay duoc, nhung
# phu thuoc vao dieu do la mong manh: chi can them mot file test thieu dong SET la
# hong voi mot thong bao rat kho hieu. (Stored procedure khong bi anh huong — chung
# gan cung thiet lap nay tai thoi diem duoc tao.)
$sqlCmdArgs = "-S", $ServerInstance, "-E", "-d", $Database, "-i", $masterFile, "-b", "-I"
$process = Start-Process -FilePath "sqlcmd" -ArgumentList $sqlCmdArgs -NoNewWindow -Wait -PassThru

if ($process.ExitCode -eq 0) {
    Write-Host "`n[PASS] All SQL Tests completed successfully!" -ForegroundColor Green
} else {
    Write-Host "`n[FAIL] SQL Tests failed. Please check the output above." -ForegroundColor Red
}

Write-Host "`nRunning Concurrency Test..." -ForegroundColor Yellow
.\11_Test_Concurrency.ps1 -ServerInstance $ServerInstance -Database $Database

Write-Host "`nRunning Venue Map Concurrency Test..." -ForegroundColor Yellow
.\14_Test_VenueMap_Concurrency.ps1 -ServerInstance $ServerInstance -Database $Database

# Chi xoa FILE SQL tam da ghep, KHONG dong vao database.
# Du lieu mock (concert/tai khoan test) CO Y o lai sau khi chay: de con soi khi co test
# do, va vi 01_SetupMockData.sql da xoa sach o dau moi lan chay nen no tu lam sach.
# Hau qua can biet: "Test Concert Live 2025" van hien CONG KHAI o trang chu voi trang
# thai OnSale cho toi lan deploy sach ke tiep. Truoc khi demo, chay lai:
#     .\scripts\setup-demo.ps1   (deploy sach)  hoac  .\scripts\seed-demo.ps1
Write-Host "`nXoa file SQL tam (du lieu mock trong database duoc giu lai)..." -ForegroundColor Yellow
Remove-Item $masterFile

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " TEST RUN COMPLETED" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
