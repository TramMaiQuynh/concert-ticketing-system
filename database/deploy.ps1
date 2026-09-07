<#
.SYNOPSIS
    Master Deployment Script -- Concert Ticketing System
    Trien khai toan bo he thong CSDL tu dau den cuoi theo dung
    thu tu phu thuoc (FK dependency order).

.PARAMETER ServerInstance
    Ten SQL Server instance. Mac dinh: localhost

.PARAMETER DatabaseName
    Ten database se tao va deploy vao. Mac dinh: ConcertTicketingDB

.PARAMETER Username
    SQL Server login (SQL Auth). De trong de dung Windows Auth.

.PARAMETER Password
    Mat khau SQL Auth. De trong de dung Windows Auth.

.PARAMETER DropExisting
    Neu $true: xoa database cu truoc khi tao lai (DEPLOY SACH).
    Neu $false (mac dinh): giu database cu, chi chay CREATE OR ALTER.

.EXAMPLE
    # Windows Auth, local server:
    .\deploy.ps1

    # SQL Auth:
    .\deploy.ps1 -Username "sa" -Password "YourPassword"

    # Deploy sach len server khac:
    .\deploy.ps1 -ServerInstance "MYSERVER\SQLEXPRESS" -DropExisting $true
#>

param(
    [string]$ServerInstance = "localhost",
    [string]$DatabaseName   = "ConcertTicketingDB",
    [string]$Username       = "",
    [string]$Password       = "",
    [bool]$DropExisting     = $false,

    # Mat khau cho 5 SQL login do he thong tao (api_service, app_admin, ...).
    # De trong -> script TU SINH mat khau ngau nhien manh va in ra chuoi ket noi
    # de dua vao cau hinh backend. Mat khau KHONG BAO GIO duoc luu trong repository.
    [string]$ApiServicePassword   = "",
    [string]$AppAdminPassword     = "",
    [string]$AppOrganizerPassword = "",
    [string]$AppCustomerPassword  = "",
    [string]$AppCheckinPassword   = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
# Helper: In tieu de phase
# ============================================================
function Write-Phase {
    param([string]$Message)
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor Cyan
    Write-Host "  $Message" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Cyan
}

# ============================================================
# Helper: Chay mot file SQL qua sqlcmd
# ============================================================
function Invoke-SqlFile {
    param(
        [string]$FilePath,
        [string]$Database = $DatabaseName,
        # Bien sqlcmd (-v). Dung de truyen mat khau vao CreateDBUsers.sql ma khong
        # phai viet chung vao file SQL.
        [hashtable]$Variables = $null
    )

    $fileName = Split-Path $FilePath -Leaf
    Write-Host "  >> $fileName" -NoNewline

    # Xay dung argument list cho sqlcmd
    # LUU Y: KHONG dung "-r1" (redirect toan bo output ra stderr). Neu dung,
    # nhung message thong thuong cua sqlcmd ("Changed database context to ...")
    # se di vao stderr; trong PowerShell 5.1 voi $ErrorActionPreference="Stop",
    # stderr cua native command bi dich lai thanh ErrorRecord -> gap Stop -> script
    # that bai ngay tu file dau tien mac du khong co loi SQL that su.
    # Viec bat loi da duoc dam bao boi "-b" (sqlcmd tra ve exit code khac 0) +
    # kiem tra $LASTEXITCODE ben duoi.
    $args = @(
        "-S", $ServerInstance,
        "-d", $Database,
        "-i", $FilePath,
        "-b",         # Exit on error
        "-I"          # SET QUOTED_IDENTIFIER ON (bat buoc cho Filtered Indexes)
    )

    if ($Variables) {
        foreach ($key in $Variables.Keys) {
            $args += @("-v", ("{0}={1}" -f $key, $Variables[$key]))
        }
    }

    if ($Username -ne "") {
        $args += @("-U", $Username, "-P", $Password)
    } else {
        $args += "-E"   # Windows Auth (Trusted Connection)
    }

    $result = & sqlcmd @args
    $exitCode = $LASTEXITCODE

    if ($exitCode -ne 0) {
        Write-Host "  [THAT BAI]" -ForegroundColor Red
        Write-Host ""
        Write-Host "Loi tai file: $FilePath" -ForegroundColor Red
        Write-Host ($result | Out-String) -ForegroundColor Red
        throw "sqlcmd that bai voi exit code $exitCode cho file: $fileName"
    }

    Write-Host "  [OK]" -ForegroundColor Green
}

# ============================================================
# Helper: Chay mot doan SQL nho truc tiep (khong qua file)
# ============================================================
function Invoke-SqlQuery {
    param(
        [string]$Query,
        [string]$Database = "master"
    )

    $tmpFile = [System.IO.Path]::GetTempFileName() + ".sql"
    $Query | Out-File -FilePath $tmpFile -Encoding UTF8

    $args = @("-S", $ServerInstance, "-d", $Database, "-i", $tmpFile, "-b", "-I")
    if ($Username -ne "") {
        $args += @("-U", $Username, "-P", $Password)
    } else {
        $args += "-E"
    }

    $result = & sqlcmd @args
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue

    if ($LASTEXITCODE -ne 0) {
        Write-Host ($result | Out-String) -ForegroundColor Red
        throw "Thuc thi SQL query that bai."
    }
}

# ============================================================
# Xac dinh duong dan goc cua du an
# ============================================================
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DbRoot    = $ScriptDir

# ============================================================
# Kiem tra sqlcmd co san khong
# ============================================================
Write-Phase "KIEM TRA TRUOC KHI DEPLOY"

try {
    $null = & sqlcmd -? 2>&1
} catch {
    Write-Host "KHONG TIM THAY sqlcmd. Vui long cai dat SQL Server command-line tools." -ForegroundColor Red
    Write-Host "Tai ve tai: https://aka.ms/sqlcmddownload" -ForegroundColor Yellow
    exit 1
}
Write-Host "  sqlcmd            [OK]" -ForegroundColor Green

# Kiem tra ket noi server
Write-Host "  Ket noi den $ServerInstance..." -NoNewline
try {
    Invoke-SqlQuery -Query "SELECT 1" -Database "master"
    Write-Host "  [OK]" -ForegroundColor Green
} catch {
    Write-Host "  [THAT BAI]" -ForegroundColor Red
    Write-Host "Khong the ket noi den SQL Server: $ServerInstance" -ForegroundColor Red
    exit 1
}

# ============================================================
# PHASE 0: Tao / Reset database
# ============================================================
Write-Phase "PHASE 0: KHOI TAO DATABASE"

if ($DropExisting) {
    Write-Host "  DropExisting = true -> Xoa database cu (neu co)..." -ForegroundColor Yellow
    Invoke-SqlQuery -Query @"
IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$DatabaseName')
BEGIN
    ALTER DATABASE [$DatabaseName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE [$DatabaseName];
    PRINT 'Da xoa database $DatabaseName.';
END
"@ -Database "master"
}

Invoke-SqlFile -FilePath (Join-Path $DbRoot "Scripts\CreateDatabase.sql") -Database "master"

# ============================================================
# PHASE 1: TABLES (theo dung thu tu FK dependency)
# Tiep can topological sort thu cong:
#   Layer 0 (khong co FK): UserAccount, Role, Artist, Venue, SystemConfiguration
#   Layer 1 (phu thuoc Layer 0): Zone, UserRoleAssignment, Concert
#   Layer 2 (phu thuoc Layer 1): Seat, TicketCategory, Waitlist, Queue, Booking, Promotion
#   Layer 3 (phu thuoc Layer 2): EventSeat, WaitlistEntry, QueueEntry, Payment, DiscountCode
#                                 CheckinStaffAssignment
#   Layer 4 (phu thuoc Layer 3): BookingEventSeatAllocation, Refund
#   Layer 5 (phu thuoc Layer 4): Ticket, BookingPromotionApplication
#   Layer 6 (phu thuoc Layer 5): CheckIn, AuditRecord
# ============================================================
Write-Phase "PHASE 1: TABLES (28 bang)"

$tablesDir = Join-Path $DbRoot "Tables"

# Layer 0 -- Khong phu thuoc bang nao khac
Invoke-SqlFile "$tablesDir\UserAccount.sql"
Invoke-SqlFile "$tablesDir\Role.sql"
Invoke-SqlFile "$tablesDir\Artist.sql"
Invoke-SqlFile "$tablesDir\Venue.sql"
Invoke-SqlFile "$tablesDir\SystemConfiguration.sql"

# Layer 1 -- Phu thuoc Layer 0
Invoke-SqlFile "$tablesDir\Zone.sql"                   # -> Venue
Invoke-SqlFile "$tablesDir\UserRoleAssignment.sql"     # -> UserAccount, Role
Invoke-SqlFile "$tablesDir\Concert.sql"                # -> UserAccount, Artist, Venue
Invoke-SqlFile "$tablesDir\RefreshToken.sql"           # -> UserAccount

# Layer 2 -- Phu thuoc Layer 1
Invoke-SqlFile "$tablesDir\Seat.sql"                   # -> Zone, Venue
Invoke-SqlFile "$tablesDir\TicketCategory.sql"         # -> Concert
Invoke-SqlFile "$tablesDir\Waitlist.sql"               # -> Concert
Invoke-SqlFile "$tablesDir\Queue.sql"                  # -> Concert
Invoke-SqlFile "$tablesDir\Booking.sql"                # -> UserAccount, Concert
Invoke-SqlFile "$tablesDir\Promotion.sql"              # -> Concert

# Layer 3 -- Phu thuoc Layer 2
Invoke-SqlFile "$tablesDir\EventSeat.sql"              # -> Concert, Seat, TicketCategory (composite)
Invoke-SqlFile "$tablesDir\WaitlistEntry.sql"          # -> Waitlist, UserAccount, Booking (nullable)
Invoke-SqlFile "$tablesDir\QueueEntry.sql"             # -> Queue, UserAccount
Invoke-SqlFile "$tablesDir\Payment.sql"                # -> Booking
Invoke-SqlFile "$tablesDir\DiscountCode.sql"           # -> Promotion
Invoke-SqlFile "$tablesDir\CheckinStaffAssignment.sql" # -> UserAccount, Concert

# Layer 4 -- Phu thuoc Layer 3
Invoke-SqlFile "$tablesDir\BookingEventSeatAllocation.sql"  # -> Booking, EventSeat
Invoke-SqlFile "$tablesDir\WaitlistEntryEventSeatAllocation.sql"
Invoke-SqlFile "$tablesDir\Refund.sql"                      # -> Payment

# Layer 5 -- Phu thuoc Layer 4
Invoke-SqlFile "$tablesDir\Ticket.sql"                      # -> Booking, EventSeat, Concert, Allocation
Invoke-SqlFile "$tablesDir\BookingPromotionApplication.sql" # -> Booking, Promotion, DiscountCode

# Layer 6 -- Phu thuoc Layer 5
Invoke-SqlFile "$tablesDir\CheckIn.sql"                     # -> Ticket, Concert, UserAccount
Invoke-SqlFile "$tablesDir\AuditRecord.sql"                 # -> UserAccount

Write-Host ""
Write-Host "  Tong cong: 28 bang da duoc tao." -ForegroundColor Green

# ============================================================
# PHASE 2: INDEXES
# Indexes duoc tao sau Tables de tranh loi "table not found".
# Filtered Unique Index can table co data type dung.
# ============================================================
Write-Phase "PHASE 2: INDEXES (operational + reporting + audit)"

$indexDir = Join-Path $DbRoot "Indexes"
Invoke-SqlFile "$indexDir\OperationalIndexes.sql"

Write-Host ""
Write-Host "  Luu y: 5 Filtered Unique Index da duoc tao inline trong Tables:" -ForegroundColor DarkGray
Write-Host "    UIX_Allocation_ActiveEventSeat      (BookingEventSeatAllocation)" -ForegroundColor DarkGray
Write-Host "    UIX_Payment_EffectivePerBooking     (Payment)" -ForegroundColor DarkGray
Write-Host "    UIX_Payment_PendingPerBooking       (Payment)" -ForegroundColor DarkGray
Write-Host "    UIX_WaitlistEntry_ActivePerCustomer (WaitlistEntry)" -ForegroundColor DarkGray
Write-Host "    UIX_QueueEntry_ActivePerCustomer    (QueueEntry)" -ForegroundColor DarkGray

# ============================================================
# PHASE 3: FUNCTIONS
# Functions phai co truoc Stored Procedures su dung chung.
#   fn_CalculateBookingSubtotal  <- duoc goi boi fn_CalculateFinalAmount
#   fn_CalculateFinalAmount      <- duoc goi boi sp_ApplyPromotion
#   fn_GetCustomerTicketCount    <- duoc goi boi sp_CreateBooking
# ============================================================
Write-Phase "PHASE 3: FUNCTIONS (3 function)"

$fnDir = Join-Path $DbRoot "Functions"
Invoke-SqlFile "$fnDir\fn_CalculateBookingSubtotal.sql"   # Phai truoc fn_CalculateFinalAmount
Invoke-SqlFile "$fnDir\fn_CalculateFinalAmount.sql"       # Goi fn_CalculateBookingSubtotal
Invoke-SqlFile "$fnDir\fn_GetCustomerTicketCount.sql"

# ============================================================
# PHASE 4: TRIGGERS
# Toan bo AFTER triggers. Thu tu trong phase nay khong co
# phu thuoc cheo nhau (moi trigger tren mot bang rieng),
# ngoai tru TRG_StateTransition chua nhieu trigger tren
# nhieu bang -> chay truoc.
# ============================================================
Write-Phase "PHASE 4: TRIGGERS (22 file, 33 trigger object) + ghim thu tu khai hoa"

$trgDir = Join-Path $DbRoot "Triggers"

# State machine triggers (10 bang: Concert, EventSeat, Booking,
# Payment, Ticket, Refund, Waitlist, WaitlistEntry, Queue, QueueEntry)
Invoke-SqlFile "$trgDir\TRG_StateTransition.sql"

# Referential integrity triggers
Invoke-SqlFile "$trgDir\TRG_SeatVenueConsistency.sql"
Invoke-SqlFile "$trgDir\TRG_EventSeatVenue.sql"
Invoke-SqlFile "$trgDir\TRG_ConcertVenueChangeGuard.sql"   # bo sung: chan doi VenueID khi Concert co EventSeat
Invoke-SqlFile "$trgDir\TRG_SeatVenueChangeGuard.sql"      # bo sung: chan doi VenueID khi Seat co EventSeat
Invoke-SqlFile "$trgDir\TRG_AllocationConcert.sql"
Invoke-SqlFile "$trgDir\TRG_TicketConcertConsistency.sql"

# Business rule triggers
Invoke-SqlFile "$trgDir\TRG_InventoryAllocationConsistency.sql"
Invoke-SqlFile "$trgDir\TRG_OneActiveTicketPerEventSeat.sql"
Invoke-SqlFile "$trgDir\TRG_PaymentEffectiveSingle.sql"
Invoke-SqlFile "$trgDir\TRG_RefundLimits.sql"
Invoke-SqlFile "$trgDir\TRG_TicketCountOnConfirm.sql"
Invoke-SqlFile "$trgDir\TRG_DiscountCodeConditional.sql"
Invoke-SqlFile "$trgDir\TRG_PromotionValidity.sql"
Invoke-SqlFile "$trgDir\TRG_Booking_DiscountUsageGuard.sql"
Invoke-SqlFile "$trgDir\TRG_EventSeatPriceConsistency.sql"
Invoke-SqlFile "$trgDir\TRG_EventSeat_PriceInsert.sql"
Invoke-SqlFile "$trgDir\TRG_WaitlistEntryAllocationConcert.sql"
Invoke-SqlFile "$trgDir\TRG_WaitlistEntryCategoryConcert.sql"

# Audit trigger (chay sau cac trigger khac de khong tu ghi audit vao chinh no)
Invoke-SqlFile "$trgDir\TRG_AuditLog.sql"
Invoke-SqlFile "$trgDir\TRG_AuditRecord_SecurityGuard.sql"

# Security trigger
Invoke-SqlFile "$trgDir\TRG_SystemActorGuard.sql"

# Ghim thu tu khai hoa -- PHAI la buoc CUOI CUNG cua Phase 4.
# CREATE OR ALTER TRIGGER reset thu tu da ghim, nen moi trigger phai ton tai truoc.
Invoke-SqlFile "$trgDir\TRG_FiringOrder.sql"

# ============================================================
# PHASE 5: STORED PROCEDURES
# sp_CreateBooking        <- goi fn_GetCustomerTicketCount
# sp_ApplyPromotion       <- goi fn_CalculateFinalAmount
# Cac SP khac khong phu thuoc nhau.
# ============================================================
Write-Phase "PHASE 5: STORED PROCEDURES (43 SP)"

$spDir = Join-Path $DbRoot "StoredProcedures"
# --- Core transaction SPs ---
Invoke-SqlFile "$spDir\sp_CreateBooking.sql"
Invoke-SqlFile "$spDir\sp_ConfirmPayment.sql"
Invoke-SqlFile "$spDir\sp_ProcessRefund.sql"
Invoke-SqlFile "$spDir\sp_CheckInTicket.sql"
Invoke-SqlFile "$spDir\sp_ReleaseExpiredHolds.sql"
Invoke-SqlFile "$spDir\sp_AllocateWaitlist.sql"
Invoke-SqlFile "$spDir\sp_ApplyPromotion.sql"
Invoke-SqlFile "$spDir\sp_RegisterUser.sql"
Invoke-SqlFile "$spDir\sp_CancelBooking.sql"
Invoke-SqlFile "$spDir\sp_InitiatePayment.sql"
Invoke-SqlFile "$spDir\sp_FailPayment.sql"
Invoke-SqlFile "$spDir\sp_ConfirmRefund.sql"
Invoke-SqlFile "$spDir\sp_UpdateRefundStatus.sql"

# --- Admin/Organizer management SPs (feature completion) ---
Invoke-SqlFile "$spDir\sp_CreateConcert.sql"
Invoke-SqlFile "$spDir\sp_UpdateConcert.sql"
Invoke-SqlFile "$spDir\sp_UpdateConcertStatus.sql"
Invoke-SqlFile "$spDir\sp_CreateVenue.sql"
Invoke-SqlFile "$spDir\sp_CreateZone.sql"
Invoke-SqlFile "$spDir\sp_CreateSeat.sql"
Invoke-SqlFile "$spDir\sp_UpdateVenue.sql"          # FR59b/BR50e: Venue -> Inactive
Invoke-SqlFile "$spDir\sp_UpdateZone.sql"           # FR59b/BR50e: Zone  -> Retired
Invoke-SqlFile "$spDir\sp_UpdateSeat.sql"           # FR59b/BR50e: Seat  -> Retired
Invoke-SqlFile "$spDir\sp_ConfigureVenueMap.sql"    # FR11a: mat phang toa do + san khau
Invoke-SqlFile "$spDir\sp_CreateArtist.sql"
Invoke-SqlFile "$spDir\sp_UpdateArtist.sql"
Invoke-SqlFile "$spDir\sp_ConfigureTicketCategory.sql"
Invoke-SqlFile "$spDir\sp_AddEventSeats.sql"
Invoke-SqlFile "$spDir\sp_CreatePromotion.sql"
Invoke-SqlFile "$spDir\sp_AssignRole.sql"
Invoke-SqlFile "$spDir\sp_UpdateRoleStatus.sql"

# --- Customer self-service SPs ---
Invoke-SqlFile "$spDir\sp_JoinWaitlist.sql"
Invoke-SqlFile "$spDir\sp_ConfigureWaitlist.sql"    # BR43 : AllocationPolicy FIFO/RANDOM
Invoke-SqlFile "$spDir\sp_ConfigureQueue.sql"       # FR64a: capacity/policy/booking_ttl
Invoke-SqlFile "$spDir\sp_JoinQueue.sql"
Invoke-SqlFile "$spDir\sp_ExitQueue.sql"

# --- Scheduled job SPs (goi boi SQL Agent) ---
Invoke-SqlFile "$spDir\sp_ProcessQueueAdmission.sql"
Invoke-SqlFile "$spDir\sp_ProcessSaleWindowTransitions.sql"

# --- Admin extended management SPs ---
Invoke-SqlFile "$spDir\sp_CreateDiscountCode.sql"
Invoke-SqlFile "$spDir\sp_UpdatePromotionStatus.sql"    # FR52: Draft/Active/Disabled
Invoke-SqlFile "$spDir\sp_UpdateDiscountCodeStatus.sql" # FR53b: thu hoi ma giam gia
Invoke-SqlFile "$spDir\sp_SetEventSeatUnavailable.sql"
Invoke-SqlFile "$spDir\sp_AdminUpdateUserStatus.sql"
Invoke-SqlFile "$spDir\sp_AddCheckinStaffAssignment.sql"

Write-Host ""
Write-Host "  Tong cong: 43 Stored Procedures da duoc tao." -ForegroundColor Green

# ============================================================
# PHASE 6: VIEWS
# Views phu thuoc Tables, khong phu thuoc SP/Trigger/Function.
# ============================================================
Write-Phase "PHASE 6: VIEWS (2 file, 11 view)"

$viewDir = Join-Path $DbRoot "Views"
Invoke-SqlFile "$viewDir\VW_ConcertSalesSummary.sql"
Invoke-SqlFile "$viewDir\VW_Others.sql"   # Chua 5 view: ActiveInventoryStatus,
                                           # CustomerBookingHistory, CheckInReport,
                                           # WaitlistQueue, AuditTrail

# ============================================================
# PHASE 7: HANGFIRE SCHEMA
# ============================================================
Write-Phase "PHASE 7: HANGFIRE SCHEMA"

$scriptsDir = Join-Path $DbRoot "Scripts"
Invoke-SqlFile "$scriptsDir\HangfireSchema.sql"

# ============================================================
# PHASE 7.5: SECURITY (RBAC)
# Tao DB Users truoc, sau do moi Grant Permissions.
# ============================================================
Write-Phase "PHASE 7.5: SECURITY (RBAC)"

$secDir = Join-Path $DbRoot "Security"

# Sinh mat khau manh cho nhung login khong duoc chi dinh tu ngoai.
# 24 byte ngau nhien tu RNGCryptoServiceProvider -> Base64 (32 ky tu), loc bo cac
# ky tu gay roi cho chuoi ket noi ADO.NET (dau ; va ') va cho sqlcmd.
function New-StrongPassword {
    $bytes = New-Object byte[] 24
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $raw = [Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', ''
    # Bao dam thoa chinh sach do phuc tap cua SQL Server (chu hoa/thuong/so/ky tu dac biet)
    return ($raw + 'Aa1#')
}

if ($ApiServicePassword   -eq "") { $ApiServicePassword   = New-StrongPassword }
if ($AppAdminPassword     -eq "") { $AppAdminPassword     = New-StrongPassword }
if ($AppOrganizerPassword -eq "") { $AppOrganizerPassword = New-StrongPassword }
if ($AppCustomerPassword  -eq "") { $AppCustomerPassword  = New-StrongPassword }
if ($AppCheckinPassword   -eq "") { $AppCheckinPassword   = New-StrongPassword }

Invoke-SqlFile "$secDir\CreateDBUsers.sql" -Variables @{
    ApiServicePwd   = $ApiServicePassword
    AdminPwd        = $AppAdminPassword
    OrganizerPwd    = $AppOrganizerPassword
    CustomerPwd     = $AppCustomerPassword
    CheckinStaffPwd = $AppCheckinPassword
}
Invoke-SqlFile "$secDir\GrantPermissions.sql"

# ============================================================
# PHASE 8: SEED DATA (Bootstrap)
# Phai sau Security vi SeedData INSERT vao bang
# duoc bao ve boi Triggers (TRG_SystemActorGuard).
# ============================================================
Write-Phase "PHASE 8: SEED DATA"

$seedFile = Join-Path $DbRoot "Scripts\PostDeployment\SeedData.sql"
Invoke-SqlFile $seedFile

# ============================================================
# HOAN TAT
# ============================================================
Write-Phase "DEPLOY HOAN TAT"

Write-Host ""
Write-Host "  He thong Concert Ticketing da duoc deploy thanh cong!" -ForegroundColor Green

# Ghi chuoi ket noi ra file de buoc cau hinh backend khong phai chep tay.
# File nay nam trong .gitignore - mat khau khong bao gio vao repository.
$connString = "Server=$ServerInstance;Database=$DatabaseName;User Id=api_service;Password=$ApiServicePassword;Max Pool Size=300;Min Pool Size=10;Connect Timeout=30;TrustServerCertificate=True;"
$outFile = Join-Path $DbRoot "..\.deploy\db-credentials.json"
$outDir = Split-Path $outFile -Parent
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

@{
    generatedAt          = (Get-Date).ToString("s")
    serverInstance       = $ServerInstance
    database             = $DatabaseName
    apiServiceConnection = $connString
    logins = @{
        api_service      = $ApiServicePassword
        app_admin        = $AppAdminPassword
        app_organizer    = $AppOrganizerPassword
        app_customer     = $AppCustomerPassword
        app_checkinstaff = $AppCheckinPassword
    }
} | ConvertTo-Json -Depth 4 | Out-File -FilePath $outFile -Encoding utf8

Write-Host ""
Write-Host "  Mat khau cac SQL login da duoc SINH NGAU NHIEN va ghi vao:" -ForegroundColor Yellow
Write-Host "    $((Resolve-Path $outFile).Path)" -ForegroundColor Yellow
Write-Host "  (thu muc .deploy nam trong .gitignore - khong bao gio vao repository)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Database  : $DatabaseName" -ForegroundColor White
Write-Host "  Server    : $ServerInstance" -ForegroundColor White
Write-Host ""
Write-Host "  Cac DB User da duoc tao:" -ForegroundColor White
Write-Host "    app_admin        -- Quan tri toan he thong" -ForegroundColor DarkGray
Write-Host "    app_organizer    -- Quan ly Concert va bao cao" -ForegroundColor DarkGray
Write-Host "    app_customer     -- Dat ve va lich su ca nhan" -ForegroundColor DarkGray
Write-Host "    app_checkinstaff -- Xac thuc ve tai cong vao" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Ket noi thu:" -ForegroundColor White
Write-Host "    sqlcmd -S $ServerInstance -d $DatabaseName -E" -ForegroundColor DarkCyan
Write-Host ""
