<#
.SYNOPSIS
    Dang ky tai khoan admin bootstrap va gan role Admin.

.DESCRIPTION
    Chay MOT LAN sau khi backend da khoi dong, tuc sau scripts/setup.ps1.

    Ly do can script rieng thay vi lam trong setup.ps1:
      setup.ps1 chi deploy database + build -- backend chua chay luc do,
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

.PARAMETER AdminEmail
    Email cua tai khoan admin. KHONG co gia tri mac dinh: email la du lieu that
    cua nguoi quan tri, va mot dia chi bia (vd. @demo.local) se nam lai vinh vien
    trong UserAccount. Neu bo qua, script se hoi.

.PARAMETER AdminPassword
    Mat khau. KHONG co gia tri mac dinh: mat khau mac dinh viet trong script la
    mat khau cua moi ban sao cua repository. Neu bo qua, script se hoi bang
    Read-Host -AsSecureString (khong hien tren man hinh, khong luu ra file).
    Phai dat dung quy dinh cua RegisterValidator: >= 8 ky tu, co chu hoa va chu so.
#>
param(
    [string]$ApiBaseUrl     = "http://localhost:5295/api",
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$DatabaseName   = "ConcertTicketingDB",
    [string]$AdminUsername  = "admin",
    [string]$AdminEmail     = "",
    [string]$AdminPassword  = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true

function Write-Step($msg) { Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "     $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "     $msg" -ForegroundColor Yellow }

# -- 0. Thu thap thong tin dang nhap ------------------------------------------
# Khong co gia tri mac dinh cho email va mat khau. Ly do:
#   - Mat khau mac dinh trong script nghia la MOI ban sao cua repository deu co
#     cung mot mat khau cho tai khoan quan tri cao nhat he thong.
#   - Email bia (@demo.local) se ton tai vinh vien trong UserAccount vi khong co
#     duong sua email trong he thong.
# Mat khau chi nam trong bien cua tien trinh: khong ghi ra file, khong in ra man
# hinh, khong truyen qua tham dong lenh (tham dong lenh hien trong lich su shell
# va trong danh sach tien trinh cua moi nguoi dung tren may).

if (-not $AdminEmail) {
    Write-Host ""
    $AdminEmail = (Read-Host "  Email cho tai khoan '$AdminUsername'").Trim()
}
if ($AdminEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
    throw "Email '$AdminEmail' khong dung dinh dang. API se tu choi voi 400."
}

if (-not $AdminPassword) {
    $secure = Read-Host "  Mat khau cho tai khoan '$AdminUsername' (>= 8 ky tu, co chu hoa va chu so)" -AsSecureString
    $bstr   = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $AdminPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
# Kiem tra NGAY tai day, khop dung RegisterValidator. De API tu choi thi thong
# bao chi la "400 Bad Request" va nguoi chay khong biet dang sai o dau.
if ($AdminPassword.Length -lt 8)   { throw "Mat khau phai co it nhat 8 ky tu." }
if ($AdminPassword -cnotmatch '[A-Z]') { throw "Mat khau phai co it nhat 1 chu hoa." }
if ($AdminPassword -notmatch '[0-9]')  { throw "Mat khau phai co it nhat 1 chu so." }

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
    email       = $AdminEmail
    password    = $AdminPassword
    displayName = "Quản trị viên"
} | ConvertTo-Json

try {
    # Invoke-RestMethod ma hoa -Body KIEU STRING bang [Text.Encoding]::Default (Windows-1252
    # tren may nay), KHONG PHAI UTF-8, du -ContentType noi charset=utf-8 hay khong. DisplayName
    # "Quản trị viên" co dau tieng Viet bi hong byte, ASP.NET Core (System.Text.Json, UTF-8
    # nghiem ngat) tu choi voi 400 "JSON value could not be converted" NGAY O displayName —
    # khong lien quan gi den "tai khoan da ton tai". Da tai hien truc tiep va xac nhan bang
    # curl thu cong. Ep gui BYTE[] UTF-8 thay vi STRING de Invoke-RestMethod gui nguyen
    # byte, khong tu y ma hoa lai.
    $regBodyBytes = [System.Text.Encoding]::UTF8.GetBytes($regBody)
    Invoke-RestMethod -Uri "$ApiBaseUrl/auth/register" -Method Post `
        -ContentType 'application/json; charset=utf-8' -Body $regBodyBytes -TimeoutSec 10 | Out-Null
    Write-Ok "Dang ky thanh cong."
} catch {
    $s = 0
    if ($_.Exception.Response) { $s = [int]$_.Exception.Response.StatusCode }
    # CHI 409 (Username da ton tai) moi duoc coi la "chay lai tren database da co
    # tai khoan nay". Truoc day 400 cung duoc coi nhu vay, va do la mot lo hong
    # that: 400 la loi du lieu dau vao (email sai dinh dang, mat khau yeu...).
    # Voi cach xu ly cu, mot lan dang ky THAT BAI vi mat khau yeu van di tiep
    # xuong buoc 3, tim thay mot tai khoan TRUNG TEN da co tu truoc, roi CAP
    # QUYEN ADMIN cho chinh tai khoan do — bang mot mat khau khong he duoc dat.
    if ($s -eq 409) {
        Write-Warn "Tai khoan '$AdminUsername' da ton tai -- dung lai tai khoan do."
    } else {
        throw "Dang ky that bai ($s): $($_.Exception.Message)"
    }
}

# -- 3. Lay UserID tu DB (chinh xac hon parse JWT) ----------------------------
Write-Step "Lay UserID cua '$AdminUsername' tu database ..."
# Truy van kem trang thai PasswordHash: tai khoan dich vu nhu 'system' co
# PasswordHash = NULL (khong the dang nhap — xem SeedData.sql). Gan role Admin
# cho mot tai khoan nhu vay la tao ra mot tai khoan quan tri khong ai dang nhap
# duoc, va te hon: no bien 'system' — tai khoan ma moi tien trinh tu dong dung —
# thanh mot tai khoan co quyen quan tri ngay khi co ai do dat mat khau cho no.
$uidRaw = & sqlcmd -S $ServerInstance -d $DatabaseName -E -h -1 -W -Q `
    "SET NOCOUNT ON; SELECT CONVERT(VARCHAR(20), UserID) + '|' + CASE WHEN PasswordHash IS NULL THEN 'NOPWD' ELSE 'HAS' END FROM UserAccount WHERE Username = '$AdminUsername';" 2>&1
$uidLine = ($uidRaw | Where-Object { $_ -match '\|' } | Select-Object -First 1)
if (-not $uidLine) {
    throw "Khong tim thay tai khoan '$AdminUsername' trong UserAccount. Dang ky da that bai?"
}
$uidParts = $uidLine.Trim().Split('|')
$userId   = $uidParts[0].Trim()
if ($uidParts[1] -ne 'HAS') {
    throw "Tai khoan '$AdminUsername' khong co mat khau (PasswordHash IS NULL) — khong duoc gan role Admin."
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
# KHONG ghi mat khau. Truoc day file nay co dong note = "Mat khau: ..." — mot
# mat khau quan tri nam nguyen van trong mot file tren dia, trong thu muc ma
# nguoi chay rat de copy sang may khac hoac gui kem khi "ban giao". Mat khau chi
# ton tai trong bien cua tien trinh nay, va chi nguoi vua nhap no biet.
$root      = Split-Path $PSScriptRoot -Parent
$deployDir = Join-Path $root ".deploy"
if (-not (Test-Path $deployDir)) { New-Item -ItemType Directory -Path $deployDir -Force | Out-Null }
@{
    bootstrappedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
    adminUsername  = $AdminUsername
    adminEmail     = $AdminEmail
    adminUserId    = [int]$userId
    note           = "Mat khau KHONG duoc luu o day (xem comment trong bootstrap-admin.ps1)."
} | ConvertTo-Json | Out-File -FilePath (Join-Path $deployDir "bootstrap-info.json") -Encoding utf8
Write-Ok "Da ghi .deploy/bootstrap-info.json (khong chua mat khau)."

Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  BOOTSTRAP HOAN TAT" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
Write-Host "  Tai khoan admin da san sang:" -ForegroundColor White
Write-Host "    Username : $AdminUsername" -ForegroundColor White
Write-Host "    Email    : $AdminEmail" -ForegroundColor White
Write-Host "    Role     : Admin" -ForegroundColor White
Write-Host ""
Write-Host "  Mat khau la gia tri ban vua nhap — he thong khong luu lai." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Mo trinh duyet: http://localhost:5173" -ForegroundColor White
Write-Host ""
