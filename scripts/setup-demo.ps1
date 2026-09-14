<#
.SYNOPSIS
    Cài đặt toàn bộ hệ thống cho buổi demo, từ đầu đến khi chạy được — một lệnh.

.DESCRIPTION
    Trình tự:
      1. Kiểm tra công cụ bắt buộc (sqlcmd, dotnet, npm).
      2. Deploy database sạch; deploy.ps1 SINH mật khẩu ngẫu nhiên cho 5 SQL login
         và ghi ra .deploy/db-credentials.json.
      3. Sinh JWT secret và Payment signature secret, ghi vào
         backend/.../appsettings.Local.json (nằm trong .gitignore).
      4. Ghi frontend/.env để Vite proxy /api tới API.
      5. Build backend và frontend.

    KHÔNG có bí mật nào nằm trong repository. Mỗi lần chạy sinh ra một bộ mới.

.PARAMETER SkipDatabase
    Bỏ qua bước deploy database (dùng khi chỉ muốn sinh lại cấu hình).
#>
param(
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$DatabaseName   = "ConcertTicketingDB",
    [string]$ApiUrl         = "http://localhost:5295",
    [string]$FrontendUrl    = "http://localhost:5173",
    [switch]$SkipDatabase
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root       = Split-Path $PSScriptRoot -Parent
$DbDir      = Join-Path $Root "database"
$ApiDir     = Join-Path $Root "backend\src\ConcertTicketing.API"
$FrontendDir= Join-Path $Root "frontend"
$DeployDir  = Join-Path $Root ".deploy"

function Write-Phase($msg) {
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $msg" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

function New-Secret {
    # 32 byte ngẫu nhiên -> Base64 (44 ký tự) — vượt yêu cầu tối thiểu 32 ký tự
    # của Program.cs cho khóa HMAC-SHA256 (256-bit).
    $bytes = New-Object byte[] 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    return [Convert]::ToBase64String($bytes)
}

# ── 1. Điều kiện tiên quyết ─────────────────────────────────────────────────
Write-Phase "1/5  KIEM TRA CONG CU"
foreach ($tool in @('sqlcmd', 'dotnet', 'npm')) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $cmd) { throw "Thieu cong cu bat buoc: $tool" }
    Write-Host ("  {0,-10} [OK]  {1}" -f $tool, $cmd.Source) -ForegroundColor DarkGray
}

# Redis là tuỳ chọn: SeatMapCache đã chịu lỗi được khi Redis không sẵn sàng.
$redis = Test-NetConnection -ComputerName localhost -Port 6379 -WarningAction SilentlyContinue
if ($redis.TcpTestSucceeded) {
    Write-Host "  redis      [OK]  localhost:6379" -ForegroundColor DarkGray
} else {
    Write-Host "  redis      [KHONG CHAY] — he thong van hoat dong, so do ghe doc thang tu DB" -ForegroundColor Yellow
}

# ── 2. Database ─────────────────────────────────────────────────────────────
if ($SkipDatabase) {
    Write-Phase "2/5  DATABASE (bo qua theo yeu cau)"
    if (-not (Test-Path (Join-Path $DeployDir "db-credentials.json"))) {
        throw "Bo qua database nhung khong tim thay .deploy/db-credentials.json. Chay lai khong kem -SkipDatabase."
    }
} else {
    Write-Phase "2/5  DEPLOY DATABASE (sach)"
    Push-Location $DbDir
    try {
        & .\deploy.ps1 -ServerInstance $ServerInstance -DatabaseName $DatabaseName -DropExisting $true | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "deploy.ps1 that bai." }
    } finally { Pop-Location }
    Write-Host "  Database da deploy sach." -ForegroundColor Green
}

$creds = Get-Content (Join-Path $DeployDir "db-credentials.json") -Raw | ConvertFrom-Json

# ── 3. Bí mật của backend ───────────────────────────────────────────────────
Write-Phase "3/5  SINH BI MAT CHO BACKEND"

# Origin được phép gọi API. Luôn giữ cả hai biến thể localhost (để người chạy trên
# chính máy server vẫn mở được bằng localhost) rồi thêm $FrontendUrl. Dùng danh sách
# duy nhất: trước đây công thức là @($FrontendUrl, ($FrontendUrl -replace 'localhost',
# '127.0.0.1')) — khi $FrontendUrl là một địa chỉ IP thì phép thay thế không khớp gì
# cả, nên mảng nhận về HAI PHẦN TỬ GIỐNG HỆT NHAU và mất luôn origin localhost.
$origins = [System.Collections.Generic.List[string]]::new()
foreach ($o in @("http://localhost:5173", "http://127.0.0.1:5173", $FrontendUrl,
                 ($FrontendUrl -replace 'localhost', '127.0.0.1'))) {
    if ($o -and -not $origins.Contains($o)) { $origins.Add($o) }
}

# Host header được phép. appsettings.json giới hạn "localhost;127.0.0.1" để chống
# Host header injection — đúng, nhưng hệ quả là MỌI request đến qua IP LAN đều bị
# HostFilteringMiddleware trả 400 "Invalid Hostname" trước khi chạm tới controller.
# Giữ nguyên lớp bảo vệ, chỉ mở thêm đúng host mà API thực sự được gọi tới.
$apiHost = ([Uri]$ApiUrl).Host
$hosts   = @("localhost", "127.0.0.1")
if ($hosts -notcontains $apiHost) { $hosts += $apiHost }

$localSettings = [ordered]@{
    ConnectionStrings = [ordered]@{ Default = $creds.apiServiceConnection }
    Jwt               = [ordered]@{ Secret  = New-Secret }
    PaymentSignature  = [ordered]@{ Secret  = New-Secret }
    AllowedHosts      = ($hosts -join ';')
    Cors              = [ordered]@{ AllowedOrigins = $origins.ToArray() }
    PaymentGateway    = [ordered]@{
        Mode               = "Simulator"
        SimulatorReturnUrl = "$FrontendUrl/payment-simulator"
    }
}
$localPath = Join-Path $ApiDir "appsettings.Local.json"
$localSettings | ConvertTo-Json -Depth 5 | Out-File -FilePath $localPath -Encoding utf8
Write-Host "  Da ghi: $localPath" -ForegroundColor Green
Write-Host "  (JWT secret va Payment signature secret moi, ngau nhien 256-bit)" -ForegroundColor DarkGray
Write-Host "  Che do cong thanh toan: Simulator (Program.cs tu choi che do nay o Production)" -ForegroundColor DarkGray

# ── 4. Cấu hình frontend ────────────────────────────────────────────────────
Write-Phase "4/5  CAU HINH FRONTEND"
"VITE_API_PROXY_TARGET=$ApiUrl`n" | Out-File -FilePath (Join-Path $FrontendDir ".env") -Encoding utf8 -NoNewline
Write-Host "  Da ghi: $(Join-Path $FrontendDir '.env')  ->  proxy /api toi $ApiUrl" -ForegroundColor Green

# ── 5. Build ────────────────────────────────────────────────────────────────
Write-Phase "5/5  BUILD"
Push-Location (Join-Path $Root "backend")
try {
    & dotnet build ConcertTicketing.sln --nologo -v q | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Build backend that bai." }
    Write-Host "  Backend  [OK]" -ForegroundColor Green
} finally { Pop-Location }

Push-Location $FrontendDir
try {
    if (-not (Test-Path "node_modules")) {
        Write-Host "  Cai dat phu thuoc frontend..." -ForegroundColor DarkGray
        & npm install --silent | Out-Null
    }
    & npm run build 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Build frontend that bai." }
    Write-Host "  Frontend [OK]" -ForegroundColor Green
} finally { Pop-Location }

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  CAI DAT HOAN TAT" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
# Chay LAN = GIAO DIEN duoc mo bang mot dia chi khong phai localhost.
#
# Thu can mo ra mang la FRONTEND, khong phai API: Vite proxy /api sang backend tu
# chinh may chu, nen backend chi can nghe localhost. Truoc day co nay suy tu $ApiUrl,
# nen chay `-FrontendUrl http://<IP>:5173` (cau hinh don gian va dung nhat) lai in ra
# huong dan `npm run dev` - lenh chi lang nghe localhost, va may kia khong vao duoc.
$frontendHost = ([Uri]$FrontendUrl).Host
$isLan = $frontendHost -notin @("localhost", "127.0.0.1")

Write-Host "  Buoc tiep theo — mo HAI cua so terminal:"
Write-Host ""
if ($isLan) {
    Write-Host "    [1] Backend :  cd backend\src\ConcertTicketing.API" -ForegroundColor White
    Write-Host "                   dotnet run" -ForegroundColor White
    Write-Host ""
    Write-Host "    [2] Frontend:  cd frontend" -ForegroundColor White
    Write-Host "                   npm run dev:lan" -ForegroundColor White
    Write-Host ""
    Write-Host "  CHE DO LAN: frontend phai dung 'npm run dev:lan' (khong phai 'npm run dev')," -ForegroundColor Yellow
    Write-Host "  vi lenh mac dinh chi lang nghe 127.0.0.1 nen may khac khong vao duoc." -ForegroundColor Yellow
    Write-Host "  Backend van chay 'dotnet run' binh thuong: Vite proxy /api sang no tu chinh" -ForegroundColor Yellow
    Write-Host "  may nay, nen backend khong can mo ra mang." -ForegroundColor Yellow
    Write-Host "  Chi can mo firewall cho DUNG cong 5173 (PowerShell quyen Administrator)." -ForegroundColor Yellow
    Write-Host ""
} else {
    Write-Host "    [1] Backend :  cd backend\src\ConcertTicketing.API" -ForegroundColor White
    Write-Host "                   dotnet run" -ForegroundColor White
    Write-Host ""
    Write-Host "    [2] Frontend:  cd frontend" -ForegroundColor White
    Write-Host "                   npm run dev" -ForegroundColor White
    Write-Host ""
}
Write-Host "  Sau khi backend chay, bootstrap tai khoan admin:"
Write-Host "                   .\scripts\bootstrap-admin.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Database dang TRONG (chi co tai khoan 'system' va 4 Role)."
Write-Host "  Moi du lieu nghiep vu duoc tao bang tay tren giao dien - xem README-DEMO.md."
Write-Host ""
Write-Host "  Giao dien: $FrontendUrl"
Write-Host ""
