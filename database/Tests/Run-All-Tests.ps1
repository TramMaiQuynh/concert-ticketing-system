# ====================================================================
# Run-All-Tests.ps1
# Chay toan bo Test Suite va in ra bao cao.
#
# CANH BAO — BO TEST NAY THAY THE TOAN BO DU LIEU CUA DATABASE DICH:
#   01_SetupMockData.sql xoa HET tai khoan ngoai 'system' o dau moi lan chay,
#   vi 12_Test_SP_AdminAndCatalog.sql yeu cau he thong co DUNG MOT Admin Active
#   (cac test 58406 "Admin cuoi cung" chi xac dinh duoc khi khong con Admin that
#   nao khac). Vi vay:
#     - CHAY TREN DATABASE KIEM THU RIENG, khong chay tren database dang van hanh.
#     - Neu database dich co tai khoan that (vd. 'admin' do bootstrap-admin.ps1
#       tao), script se DUNG NGAY va khong lam gi ca. Dung -Force de bo qua canh
#       bao nay khi ban thuc su muon.
#   Cuoi moi lan chay, Teardown-MockData.sql dua database ve trang thai sau
#   deploy (chi con 4 Role + 'system').
# ====================================================================

param (
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$Database = "ConcertTicketingDB",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $scriptDir

# -- Chan truoc khi pha: bo test se xoa moi tai khoan ngoai fixture ------------
# Quy uoc dat ten fixture: 'test_*' hoac 'tmp_*' (xem Teardown-MockData.sql).
$realAccountsRaw = & sqlcmd -S $ServerInstance -E -d $Database -h -1 -W -Q `
    "SET NOCOUNT ON; SELECT Username FROM UserAccount WHERE Username NOT LIKE 'test[_]%' AND Username NOT LIKE 'tmp[_]%' AND Username <> 'system' ORDER BY Username" 2>&1
$realAccounts = @($realAccountsRaw | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*$' } | ForEach-Object { $_.Trim() })
if ($realAccounts.Count -gt 0 -and -not $Force) {
    Write-Host ""
    Write-Host "DUNG LAI: database '$Database' co tai khoan THAT, khong phai fixture test:" -ForegroundColor Red
    $realAccounts | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Bo test se XOA cac tai khoan nay (01_SetupMockData.sql xoa het tai khoan ngoai 'system'," -ForegroundColor Yellow
    Write-Host "vi cac test ve 'Admin Active cuoi cung' doi hoi he thong chi co DUNG MOT Admin)." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Hay chay tren mot database kiem thu rieng:" -ForegroundColor Yellow
    Write-Host "    .\Run-All-Tests.ps1 -Database ConcertTicketingDB_Test" -ForegroundColor White
    Write-Host ""
    Write-Host "Hoac chap nhan mat cac tai khoan tren: them -Force" -ForegroundColor Yellow
    exit 1
}

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

# Don sach: xoa FILE SQL tam da ghep, roi DON DU LIEU MOCK trong database.
#
# Truoc day du lieu mock duoc CO Y giu lai "de con soi khi co test do". Nhung hau qua
# la "Test Concert Live 2025" van hien CONG KHAI o trang chu voi trang thai OnSale cho
# toi lan deploy sach ke tiep — mot database nhu vay khong dung de ban giao.
#
# Teardown chay o day, tuc SAU CUNG: phai sau ca hai bai kiem dong thoi ben tren, vi
# 11_Test_Concurrency.ps1 can du lieu mock con nguyen (@ConcertID, test_cust1).
#
# Teardown-MockData.sql KHONG khop ^\d{2}_ nen KHONG bi gop vao master file o tren:
# no buoc phai chay sau cung, khong the nam chung danh sach voi cac file test.
Write-Host "`nXoa file SQL tam..." -ForegroundColor Yellow
Remove-Item $masterFile

Write-Host "Don du lieu mock (dua database ve trang thai sau deploy)..." -ForegroundColor Yellow
$teardownFile = Join-Path $scriptDir "Teardown-MockData.sql"
$teardownArgs = "-S", $ServerInstance, "-E", "-d", $Database, "-i", $teardownFile, "-b", "-I"
$teardownProc = Start-Process -FilePath "sqlcmd" -ArgumentList $teardownArgs -NoNewWindow -Wait -PassThru
if ($teardownProc.ExitCode -eq 0) {
    Write-Host "[PASS] Da don du lieu mock — database tro ve trang thai sau deploy." -ForegroundColor Green
} else {
    Write-Host "[FAIL] Don du lieu mock that bai. Xem thong bao o tren." -ForegroundColor Red
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " TEST RUN COMPLETED" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
