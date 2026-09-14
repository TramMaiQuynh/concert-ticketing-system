<#
.SYNOPSIS
    Nạp dữ liệu demo sẵn (tùy chọn — KHÔNG dùng trong luồng bảo vệ chính).

.DESCRIPTION
    Script này phục vụ demo NHANH khi cần dữ liệu sẵn (3 concert, 4 tài khoản).
    Luồng bảo vệ chính dùng database HOÀN TOÀN TRỐNG và xây dựng mọi thứ LIVE
    trên giao diện — xem README-DEMO.md §4 để biết chi tiết.

    Nếu vẫn muốn dùng script này: chạy SAU bootstrap-admin.ps1, vì script này
    tạo thêm 3 tài khoản demo_admin / demo_organizer / demo_customer / demo_staff.
    KHÔNG idempotent — chạy lần hai mà chưa deploy lại database sẽ lỗi trùng tài khoản.

    Toàn bộ dữ liệu được tạo QUA API THẬT, không INSERT thẳng vào bảng.
    Đi qua API nghĩa là mọi stored procedure, trigger, ràng buộc CHECK và kiểm tra
    phân quyền đều được thực thi — bản thân việc seed chạy trót lọt đã là bằng chứng.
    (Ngoại lệ: gán quyền Admin đầu tiên phải làm bằng SQL — bài toán "con gà quả trứng".)

.PARAMETER ApiBaseUrl
    Địa chỉ gốc của API. Mặc định http://localhost:5295/api

.PARAMETER ServerInstance
    SQL Server instance, dùng cho đúng một bước bootstrap quyền Admin.
#>
param(
    [string]$ApiBaseUrl     = "http://localhost:5295/api",
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$DatabaseName   = "ConcertTicketingDB"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PSDefaultParameterValues['Invoke-WebRequest:UseBasicParsing'] = $true

$DemoPassword = "Demo@12345"

function Write-Step($msg) { Write-Host "  -> $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "     $msg" -ForegroundColor DarkGray }

function Invoke-Api {
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Path,
        $Body = $null,
        [string]$Token = $null
    )
    $headers = @{}
    if ($Token) { $headers['Authorization'] = "Bearer $Token" }

    $params = @{ Method = $Method; Uri = "$ApiBaseUrl$Path"; Headers = $headers; ContentType = 'application/json' }
    if ($null -ne $Body) { $params['Body'] = ($Body | ConvertTo-Json -Depth 6) }

    # Endpoint /auth/* bi gioi han 5 request/phut moi IP de chong Brute Force
    # (Program.cs, policy "auth"). Script nay tao 4 tai khoan roi dang nhap lai 3 lan
    # sau khi gan Role -> vuot han muc. Khong duoc noi long bao ve chi vi tien cho
    # script seed: cach dung la TON TRONG gioi han va cho het cua so thoi gian.
    for ($attempt = 1; $attempt -le 4; $attempt++) {
        try {
            return Invoke-RestMethod @params
        } catch {
            $status = 0
            if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }

            if ($status -eq 429 -and $attempt -lt 4) {
                Write-Host "     (dat gioi han tan suat — cho 62 giay roi thu lai, lan $attempt/3)" -ForegroundColor DarkYellow
                Start-Sleep -Seconds 62   # cua so co dinh 1 phut + du phong
                continue
            }

            $detail = ""
            if ($_.Exception.Response) {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $detail = $reader.ReadToEnd()
            }
            throw "API $Method $Path that bai: $($_.Exception.Message)`n$detail"
        }
    }
}

function Register-User($username, $displayName) {
    $body = @{ username = $username; email = "$username@demo.local"; password = $DemoPassword; displayName = $displayName }
    try {
        $res = Invoke-Api -Method Post -Path "/auth/register" -Body $body
        return $res.accessToken
    } catch {
        # Đã tồn tại (chạy seed lần hai) -> đăng nhập lại.
        $res = Invoke-Api -Method Post -Path "/auth/login" -Body @{ username = $username; password = $DemoPassword }
        return $res.accessToken
    }
}

function Get-UserId($token) {
    $payload = $token.Split('.')[1].Replace('-', '+').Replace('_', '/')
    switch ($payload.Length % 4) { 2 { $payload += '==' } 3 { $payload += '=' } }
    $claims = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
    return [int]$claims.sub
}

function Invoke-Sql($query) {
    $tmp = [IO.Path]::GetTempFileName()
    Set-Content -Path $tmp -Value $query -Encoding UTF8
    $out = & sqlcmd -S $ServerInstance -d $DatabaseName -E -b -I -i $tmp 2>&1
    $code = $LASTEXITCODE
    Remove-Item $tmp -Force
    if ($code -ne 0) { throw "sqlcmd that bai:`n$($out | Out-String)" }
    return $out
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  NAP DU LIEU DEMO" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ── 1. Tài khoản ────────────────────────────────────────────────────────────
Write-Step "Tao 4 tai khoan demo (qua /auth/register — BCrypt that)"
$adminToken     = Register-User "demo_admin"     "Quan tri vien Demo"
$organizerToken = Register-User "demo_organizer" "Nha to chuc Demo"
$customerToken  = Register-User "demo_customer"  "Khach hang Demo"
$staffToken     = Register-User "demo_staff"     "Nhan vien soat ve"

$adminId     = Get-UserId $adminToken
$organizerId = Get-UserId $organizerToken
$customerId  = Get-UserId $customerToken
$staffId     = Get-UserId $staffToken
Write-Ok "admin=$adminId organizer=$organizerId customer=$customerId staff=$staffId"

# ── 2. Bootstrap quyền Admin ────────────────────────────────────────────────
# Bước DUY NHẤT phải dùng SQL: sp_AssignRole yêu cầu người gọi đã là Admin, nên
# Admin đầu tiên của hệ thống không thể tạo ra qua chính API đó.
Write-Step "Bootstrap quyen Admin cho demo_admin (buoc duy nhat dung SQL truc tiep)"
Invoke-Sql @"
IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura
               JOIN Role r ON r.RoleID = ura.RoleID
               WHERE ura.UserID = $adminId AND r.RoleName = 'Admin')
    INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
    SELECT $adminId, RoleID, 'Active' FROM Role WHERE RoleName = 'Admin';
ELSE
    UPDATE ura SET AssignmentStatus = 'Active'
    FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
    WHERE ura.UserID = $adminId AND r.RoleName = 'Admin';
"@ | Out-Null

# Token cũ chưa có claim Admin -> đăng nhập lại để lấy token mang đúng vai trò.
$adminToken = (Invoke-Api -Method Post -Path "/auth/login" -Body @{ username = "demo_admin"; password = $DemoPassword }).accessToken
Write-Ok "Da cap quyen Admin va lay token moi"

# ── 3. Phân vai trò cho các tài khoản còn lại (qua API, đúng luồng nghiệp vụ) ─
Write-Step "Gan Role Organizer va Check-in Staff (qua /admin/roles/assign)"
Invoke-Api -Method Post -Path "/admin/roles/assign" -Token $adminToken `
    -Body @{ targetUserId = $organizerId; roleName = "Organizer"; grantOrRevoke = "Grant" } | Out-Null
Invoke-Api -Method Post -Path "/admin/roles/assign" -Token $adminToken `
    -Body @{ targetUserId = $staffId; roleName = "Check-in Staff"; grantOrRevoke = "Grant" } | Out-Null

$organizerToken = (Invoke-Api -Method Post -Path "/auth/login" -Body @{ username = "demo_organizer"; password = $DemoPassword }).accessToken
$staffToken     = (Invoke-Api -Method Post -Path "/auth/login" -Body @{ username = "demo_staff";     password = $DemoPassword }).accessToken
Write-Ok "Da gan va lam moi token"

# ── 4. Danh mục: Artist + Venue + Zone + Seat ───────────────────────────────
$stamp = Get-Date -Format 'HHmmss'

Write-Step "Tao Artist va Venue (chi Admin — sp_CreateArtist/sp_CreateVenue)"
$artistId = Invoke-Api -Method Post -Path "/admin/artists" -Token $adminToken `
    -Body @{ artistName = "Ban nhac Demo $stamp"; artistDescription = "Nghe si phuc vu demo" }
$artistId = [int]$artistId.id
$venueId  = Invoke-Api -Method Post -Path "/admin/venues" -Token $adminToken `
    -Body @{ venueName = "Nha hat Demo $stamp"; address = "1 Duong Demo, Q1, TP.HCM" }
$venueId = [int]$venueId.id
Write-Ok "artistId=$artistId venueId=$venueId"

# ── So do khan phong (FR11a) ────────────────────────────────────────────────
#
# Truoc day seeder tao 2 khu "phang": khong toa do, khong hang, khong san khau.
# Hau qua o giao dien: so do chi la mot day hinh tron, khach khong biet cho ngoi
# cua minh nam o dau trong khan phong — ma do lai chinh la yeu to quyet dinh gia
# tri mot chiec ve.
#
# Khan phong duoi day co hinh dang that: san khau o tren, khu dung sat san khau,
# khoi VIP chinh dien, hai khoi thuong hai ben XOAY huong ve san khau.
#
# Don vi la so nguyen TRU TUONG — giao dien co gian toan bo so do vao khung hinh
# dang co, nen khong can du lieu do dac thuc dia.
Write-Step "Khai bao so do khan phong (mat phang 1000x720, san khau o tren)"
Invoke-Api -Method Put -Path "/admin/venues/$venueId/map" -Token $adminToken -Body @{
    mapWidth = 1000; mapHeight = 720
    stageX = 320; stageY = 24; stageWidth = 360; stageHeight = 56
} | Out-Null
Write-Ok "Da dat mat phang va san khau"

Write-Step "Tao 4 khu: 1 khu ve dung + 3 khoi ghe"

# Khu ve DUNG: khong co ghe danh so, ban theo suc chua. Concert gan nhu luon co
# loai khu nay; mo hinh hoa no bang hang tram dong Seat gia la sai ban chat.
Invoke-Api -Method Post -Path "/admin/venues/$venueId/zones" -Token $adminToken -Body @{
    zoneCode = "PIT$stamp"; zoneName = "Khu dung truoc san khau"
    zoneType = 'GeneralAdmission'; zoneCapacity = 200
    zoneLevel = 1; zoneX = 340; zoneY = 120; zoneWidth = 320; zoneHeight = 100
} | Out-Null

# Ba khoi ghe. Hai khoi hai ben duoc XOAY huong ve san khau — dieu khong the bieu
# dien duoc neu chi luu 'trai/giua/phai'.
$blocks = @(
    @{ Key = 'VIP';   Code = "VIP$stamp";  Name = 'Khu VIP';          X = 280; Y = 250; W = 440; H = 130; Rot = 0;   Rows = @('A','B'); Cols = 6 },
    @{ Key = 'STD_L'; Code = "STDL$stamp"; Name = 'Khu thuong trai';  X =  60; Y = 420; W = 330; H = 170; Rot = 10;  Rows = @('C','D'); Cols = 3 },
    @{ Key = 'STD_R'; Code = "STDR$stamp"; Name = 'Khu thuong phai';  X = 610; Y = 420; W = 330; H = 170; Rot = -10; Rows = @('C','D'); Cols = 3 }
)

$zones = @{}
$seatIds = @{ 'VIP' = @(); 'STD' = @() }

foreach ($b in $blocks) {
    $r = Invoke-Api -Method Post -Path "/admin/venues/$venueId/zones" -Token $adminToken -Body @{
        zoneCode = $b.Code; zoneName = $b.Name
        zoneType = 'Seated'; zoneLevel = 1
        zoneX = $b.X; zoneY = $b.Y; zoneWidth = $b.W; zoneHeight = $b.H; zoneRotation = $b.Rot
    }
    $zones[$b.Key] = [int]$r.id

    # Ghe duoc tao kem HANG va SO THU TU TRONG HANG. Do moi la vi tri; SeatCode
    # chi la dinh danh. Thieu hai truong nay thi khong the ve dung cho ngoi, va
    # cung khong the in ra dia chi ma nguoi thuong hieu duoc ('Khu VIP, hang A, ghe 3').
    foreach ($row in $b.Rows) {
        for ($c = 1; $c -le $b.Cols; $c++) {
            $seat = Invoke-Api -Method Post -Path "/admin/zones/$($zones[$b.Key])/seats" -Token $adminToken -Body @{
                seatCode = "$($b.Code)-$row$c"
                seatLabel = "$row$c"
                seatRowLabel = $row
                seatColumnNumber = $c
            }
            # Hai khoi thuong gop chung vao mot hang ve 'STD'.
            $bucket = $(if ($b.Key -eq 'VIP') { 'VIP' } else { 'STD' })
            $seatIds[$bucket] += [int]$seat.id
        }
    }
}
Write-Ok "VIP: $($seatIds['VIP'].Count) ghe, Thuong: $($seatIds['STD'].Count) ghe, + 1 khu dung 200 cho"

# ── 5. Ba Concert minh hoạ ba luồng nghiệp vụ khác nhau ─────────────────────
function New-Concert($name, $fairAccess, $waitlist, $daysAhead) {
    $start = (Get-Date).AddDays($daysAhead)
    $body = @{
        artistId              = $artistId
        venueId               = $venueId
        concertName           = $name
        startDatetime         = $start.ToString("s")
        endDatetime           = $start.AddHours(3).ToString("s")
        saleStartDatetime     = (Get-Date).AddDays(-1).ToString("s")
        saleEndDatetime       = $start.AddDays(-1).ToString("s")
        purchaseLimit         = 4
        temporaryHoldDuration = 900
        fairAccessEnabled     = $fairAccess
        waitlistEnabled       = $waitlist
        salesPaused           = $false
        cancellationPolicy    = "Huy truoc 48 gio duoc hoan 100%"
        refundPolicy          = "Hoan 100% theo chinh sach"
        cancellationDeadlineHours = 48
        refundPercentage      = 100
    }
    # Concert do chinh Organizer tao — AdminController lay actor tu JWT lam OrganizerUserID.
    $r = Invoke-Api -Method Post -Path "/admin/concerts" -Token $organizerToken -Body $body
    return [int]$r.id
}

function Complete-Concert($concertId, $vipSeats, $stdSeats) {
    $vipCat = Invoke-Api -Method Post -Path "/admin/concerts/$concertId/categories" -Token $organizerToken `
        -Body @{ categoryName = "VIP"; categoryDescription = "Hang ghe VIP"; basePrice = 1500000 }
    $stdCat = Invoke-Api -Method Post -Path "/admin/concerts/$concertId/categories" -Token $organizerToken `
        -Body @{ categoryName = "Thuong"; categoryDescription = "Hang ghe thuong"; basePrice = 500000 }

    Invoke-Api -Method Post -Path "/admin/concerts/$concertId/event-seats" -Token $organizerToken `
        -Body @{ ticketCategoryId = [int]$vipCat.id; seatIds = $vipSeats } | Out-Null
    Invoke-Api -Method Post -Path "/admin/concerts/$concertId/event-seats" -Token $organizerToken `
        -Body @{ ticketCategoryId = [int]$stdCat.id; seatIds = $stdSeats } | Out-Null

    # Draft -> Published -> OnSale (state machine BR49; OnSale doi BR10: da co kho ve
    # va da cau hinh cua so ban)
    # Luu y: doi trang thai Concert la [HttpPatch], khong phai PUT.
    Invoke-Api -Method Patch -Path "/admin/concerts/$concertId/status" -Token $organizerToken -Body @{ status = "Published" } | Out-Null
    Invoke-Api -Method Patch -Path "/admin/concerts/$concertId/status" -Token $organizerToken -Body @{ status = "OnSale" }    | Out-Null
}

Write-Step "Concert 1 — ban ve thong thuong"
$c1 = New-Concert "Dem nhac Demo — Ban thuong" $false $false 30
Complete-Concert $c1 $seatIds['VIP'][0..5] $seatIds['STD'][0..5]
Write-Ok "concertId=$c1"

Write-Step "Concert 2 — bat Fair Access (hang doi truy cap cong bang)"
$c2 = New-Concert "Dem nhac Demo — Fair Access" $true $false 45
Complete-Concert $c2 $seatIds['VIP'][6..8] $seatIds['STD'][6..8]
Invoke-Api -Method Put -Path "/admin/concerts/$c2/queue" -Token $organizerToken `
    -Body @{ admissionCapacity = 2; fairAccessPolicy = "FIFO"; admissionValiditySeconds = 600; queueStatus = "Open" } | Out-Null
Write-Ok "concertId=$c2 (AdmissionCapacity=2, FIFO)"

Write-Step "Concert 3 — bat Waitlist (danh sach cho)"
$c3 = New-Concert "Dem nhac Demo — Waitlist" $false $true 60
Complete-Concert $c3 $seatIds['VIP'][9..11] $seatIds['STD'][9..11]
Invoke-Api -Method Put -Path "/admin/concerts/$c3/waitlist" -Token $organizerToken `
    -Body @{ allocationPolicy = "FIFO"; waitlistStatus = "Open" } | Out-Null
Write-Ok "concertId=$c3"

# ── 6. Khuyến mãi + mã giảm giá ─────────────────────────────────────────────
Write-Step "Tao Promotion va Discount Code cho Concert 1"
$promo = Invoke-Api -Method Post -Path "/admin/concerts/$c1/promotions" -Token $organizerToken -Body @{
    promotionName        = "Giam gia ra mat"
    promotionDescription = "Giam 200.000d cho don hang"
    discountType         = "Fixed Amount"
    discountValue        = 200000
    startDatetime        = (Get-Date).AddDays(-1).ToString("s")
    endDatetime          = (Get-Date).AddDays(30).ToString("s")
    usageLimit           = 100
    codeRequiredFlag     = $true
}
Invoke-Api -Method Post -Path "/admin/promotions/$([int]$promo.id)/discount-codes" -Token $adminToken -Body @{
    codeValue             = "DEMO200K"
    validFromDatetime     = (Get-Date).AddDays(-1).ToString("s")
    validToDatetime       = (Get-Date).AddDays(30).ToString("s")
    globalUsageLimit      = 50
    perCustomerUsageLimit = 2
} | Out-Null
Write-Ok "Ma giam gia: DEMO200K (giam 200.000d)"

# ── 7. Phân công nhân viên soát vé ──────────────────────────────────────────
Write-Step "Phan cong demo_staff soat ve cho ca 3 concert"
Invoke-Api -Method Post -Path "/admin/checkin-staff-assignments" -Token $adminToken `
    -Body @{ staffUserId = $staffId; concertIds = @($c1, $c2, $c3); assignmentStatus = "Active" } | Out-Null

# ── Tóm tắt ─────────────────────────────────────────────────────────────────
$summary = [ordered]@{
    password  = $DemoPassword
    accounts  = [ordered]@{
        demo_admin     = "Admin — quan tri danh muc, phan quyen"
        demo_organizer = "Organizer — tao/quan ly concert cua minh"
        demo_customer  = "Customer — dat ve, thanh toan"
        demo_staff     = "Check-in Staff — soat ve tai cong"
    }
    concerts  = [ordered]@{
        binhThuong = $c1
        fairAccess = $c2
        waitlist   = $c3
    }
    discountCode = "DEMO200K"
}
$outFile = Join-Path (Split-Path $PSScriptRoot -Parent) ".deploy\demo-data.json"
$summary | ConvertTo-Json -Depth 5 | Out-File -FilePath $outFile -Encoding utf8

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  DU LIEU DEMO DA SAN SANG" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Mat khau chung cho moi tai khoan demo: $DemoPassword"
Write-Host ""
Write-Host "    demo_admin      Admin            — quan tri danh muc, phan quyen"
Write-Host "    demo_organizer  Organizer        — tao va quan ly concert"
Write-Host "    demo_customer   Customer         — dat ve va thanh toan"
Write-Host "    demo_staff      Check-in Staff   — soat ve tai cong"
Write-Host ""
Write-Host "  Concert #$c1  ban ve thong thuong"
Write-Host "  Concert #$c2  bat Fair Access (suc chua hang doi = 2)"
Write-Host "  Concert #$c3  bat Waitlist"
Write-Host "  Ma giam gia:  DEMO200K  (giam 200.000d)"
Write-Host ""
