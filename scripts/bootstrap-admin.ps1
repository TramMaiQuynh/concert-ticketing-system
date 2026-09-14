<#
.SYNOPSIS
    Dang ky tai khoan admin bootstrap va gan role Admin.

.DESCRIPTION
    Chay MOT LAN sau khi backend da khoi dong, ngay sau setup-demo.ps1.

    Ly do can script rieng thay vi lam trong setup-demo.ps1:
      setup-demo.ps1 chi deploy database + build -- backend chua chay luc do,
      nen khong goi API duoc. Script nay chay sau khi backend da len.

    Bai toan "con ga qua trung":
      sp_AssignRole yeu cau nguoi goi da la Admin, nhung Admin dau tien chua
      ton tai. Giai phap duy nhat: INSERT truc tiep vao UserRoleAssignment bang
      sqlcmd. Day la lan duy nhat trong toan he thong phai lam vay.

.PARAMETER ApiBaseUrl
    Dia chi API. Mac dinh http://localhost:5295/api

.PARAMETER ServerInstance
    SQL Server instance. Mac dinh .\SQLEXPRESS

.PARAMETER DatabaseName
    Ten database. Mac dinh ConcertTicketingDB

.PARAMETER AdminUsername
    Ten tai khoan admin. Mac dinh admin

.PARAMETER AdminPassword
    Mat khau. Mac dinh Demo@12345
#>
param(
    [string]$ApiBaseUrl     = "http://localhost:5295/api",
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$DatabaseName   = "ConcertTicketingDB",
    [string]$AdminUsername  = "admin",
    [string]$AdminPassword  = "Demo@12345"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true

function Write-Step($msg) { Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "     $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "     $msg" -ForegroundColor Yellow }

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  BOOTSTRAP ADMIN" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

# -- 1. Kiem tra API dang chay ------------------------------------------------
Write-Step "Kiem tra API dang chay tai $ApiBaseUrl ..."
$maxRetry = 12
for ($i = 1; $i -le $maxRetry; $i++) {
    try {
        $testBody = '{"username":"_probe_","password":"_probe_"}'
        Invoke-RestMethod -Uri "$ApiBaseUrl/auth/login" -Method Post `
            -ContentType 'application/json' -Body $testBody -TimeoutSec 3 | Out-Null
        break
    } catch {
        $s = 0
        if ($_.Exception.Response) { $s = [int]$_.Exception.Response.StatusCode }
        if ($s -ge 400 -and $s -lt 500) { break }   # API dang chay, chi sai credentials
        if ($i -ge $maxRetry) {
            throw "API khong phan hoi sau $maxRetry lan thu. Hay chac chan 'dotnet run' da chay."
        }
        Write-Host "     API chua san sang, cho 5 giay... ($i/$maxRetry)" -ForegroundColor DarkGray
        Start-Sleep -Seconds 5
    }
}
Write-Ok "API dang chay."

# -- 2. Dang ky tai khoan admin -----------------------------------------------
Write-Step "Dang ky tai khoan '$AdminUsername' qua /auth/register ..."
$regBody = [ordered]@{
    username    = $AdminUsername
    email       = "$AdminUsername@demo.local"
    password    = $AdminPassword
    displayName = "Quan tri vien"
} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$ApiBaseUrl/auth/register" -Method Post `
        -ContentType 'application/json' -Body $regBody -TimeoutSec 10 | Out-Null
    Write-Ok "Dang ky thanh cong."
} catch {
    $s = 0
    if ($_.Exception.Response) { $s = [int]$_.Exception.Response.StatusCode }
    if ($s -eq 409 -or $s -eq 400) {
        Write-Warn "Tai khoan '$AdminUsername' co the da ton tai -- thu gan role lai."
    } else {
        throw "Dang ky that bai ($s): $($_.Exception.Message)"
    }
}

# -- 3. Lay UserID tu DB (chinh xac hon parse JWT) ----------------------------
Write-Step "Lay UserID cua '$AdminUsername' tu database ..."
$uidRaw = & sqlcmd -S $ServerInstance -d $DatabaseName -E -h -1 -W `
    -Q "SET NOCOUNT ON; SELECT UserID FROM UserAccount WHERE Username='$AdminUsername'" 2>&1
$userId = ($uidRaw | Where-Object { $_ -match '^\s*\d+\s*$' } | Select-Object -First 1)
if ($userId) { $userId = $userId.Trim() }
if (-not $userId) {
    throw "Khong tim thay UserID cho '$AdminUsername'. Kiem tra dang ky co thanh cong khong."
}
Write-Ok "UserID = $userId"

# -- 4. Gan role Admin bang sqlcmd (con ga qua trung) -------------------------
Write-Step "Gan role Admin cho UserID=$userId ..."
$grantSql = @"
SET NOCOUNT ON;
DECLARE @roleId INT = (SELECT RoleID FROM Role WHERE RoleName='Admin');
IF @roleId IS NULL
    THROW 50001, 'Role Admin khong ton tai. Database da deploy chua?', 1;
IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment WHERE UserID=$userId AND RoleID=@roleId)
BEGIN
    INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
    VALUES ($userId, @roleId, 'Active');
    PRINT 'Role Admin da duoc gan.';
END
ELSE
BEGIN
    UPDATE UserRoleAssignment
    SET AssignmentStatus='Active'
    WHERE UserID=$userId AND RoleID=@roleId AND AssignmentStatus != 'Active';
    PRINT 'Role Admin da ton tai -- dam bao Active.';
END
"@

$tmpFile = [IO.Path]::GetTempFileName() + ".sql"
Set-Content -Path $tmpFile -Value $grantSql -Encoding UTF8
$sqlOut = & sqlcmd -S $ServerInstance -d $DatabaseName -E -I -b -i $tmpFile 2>&1
Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
if ($LASTEXITCODE -ne 0) { throw "sqlcmd that bai:`n$($sqlOut | Out-String)" }
$sqlMsg = $sqlOut | Where-Object { $_ -match '\S' } | Select-Object -First 1
Write-Ok $sqlMsg

# -- 5. Xac nhan: login + goi endpoint can role Admin -------------------------
Write-Step "Xac nhan: dang nhap va goi /admin/artists ..."
$loginRes = Invoke-RestMethod -Uri "$ApiBaseUrl/auth/login" -Method Post `
    -ContentType 'application/json' `
    -Body ([ordered]@{ username = $AdminUsername; password = $AdminPassword } | ConvertTo-Json) `
    -TimeoutSec 10
$token = $loginRes.accessToken
if (-not $token) { throw "Dang nhap thanh cong nhung khong nhan duoc token." }

try {
    Invoke-RestMethod -Uri "$ApiBaseUrl/admin/artists" -Method Get `
        -Headers @{ Authorization = "Bearer $token" } -TimeoutSec 10 | Out-Null
    Write-Ok "GET /admin/artists -> 200 OK (role Admin da co hieu luc)."
} catch {
    $s = 0
    if ($_.Exception.Response) { $s = [int]$_.Exception.Response.StatusCode }
    throw "Xac nhan that bai: GET /admin/artists tra ve $s. Role co the chua ap dung."
}

# -- 6. Ghi thong tin ra .deploy/ ---------------------------------------------
$root      = Split-Path $PSScriptRoot -Parent
$deployDir = Join-Path $root ".deploy"
if (-not (Test-Path $deployDir)) { New-Item -ItemType Directory -Path $deployDir -Force | Out-Null }
@{
    bootstrappedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    adminUsername  = $AdminUsername
    adminUserId    = [int]$userId
    note           = "Mat khau: $AdminPassword"
} | ConvertTo-Json | Out-File -FilePath (Join-Path $deployDir "bootstrap-info.json") -Encoding utf8
Write-Ok "Da ghi .deploy/bootstrap-info.json"

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  BOOTSTRAP HOAN TAT" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Write-Host "  Tai khoan admin da san sang:" -ForegroundColor White
Write-Host "    Username : $AdminUsername" -ForegroundColor White
Write-Host "    Password : $AdminPassword" -ForegroundColor White
Write-Host "    Role     : Admin" -ForegroundColor White
Write-Host ""
Write-Host "  Mo trinh duyet: http://localhost:5173" -ForegroundColor White
Write-Host ""
