# ====================================================================
# 14_Test_VenueMap_Concurrency.ps1
# Test tranh chap dong thoi giua sp_ConfigureVenueMap va sp_CreateZone/sp_UpdateZone.
#
# BOI CANH LOI DA SUA:
# Ca ba thu tuc cung doc/ghi Venue.MapWidth/MapHeight de kiem tra bat bien "Zone
# nam trong mat phang cua Venue". sp_ConfigureVenueMap tu truoc da khoa dong Venue
# bang WITH (UPDLOCK) khi doc, nhung sp_CreateZone/sp_UpdateZone truoc day doc
# thuong (khong khoa). Da chung minh bang thuc nghiem (dong bo qua
# sys.dm_exec_requests.wait_type): mot lenh thu nho mat phang dang chay song
# song co the CHUA COMMIT gia tri moi luc sp_CreateZone/sp_UpdateZone doc, nen
# khu duoc tao/di chuyen hop le voi mat phang CU roi mat phang bi thu nho ngay
# sau do - khu troi ra ngoai bien ma ca hai thao tac deu bao "thanh cong".
#
# FIX: them WITH (UPDLOCK) vao doc Venue trong sp_CreateZone/sp_UpdateZone, dong
# bo voi UPDLOCK san co cua sp_ConfigureVenueMap tren CUNG DONG Venue do.
#
# CACH TEST KHONG CAN SUA/KHOI PHUC SP THAT (an toan cho CI, khong co rui ro de
# lai mot ban SP thu nghiem neu test crash giua chung):
# Connection A tu giu UPDLOCK tren dong Venue bang mot giao dich T-SQL tho -
# hanh vi khoa nay GIONG HET voi buoc dau cua sp_ConfigureVenueMap, vi ca hai
# cung khoa dung mot dong bang dung mot loai hint. Trong luc A dang giu khoa,
# goi sp_CreateZone/sp_UpdateZone THAT (khong sua doi mot ky tu nao) tu
# Connection B. Neu fix dung: B phai CHO (bi khoa) cho toi khi A nha khoa, roi
# doc duoc gia tri MOI NHAT chu khong phai gia tri cu da lac hau.
# ====================================================================
param (
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$Database = "ConcertTicketingDB"
)

Add-Type -AssemblyName System.Data
$cs = "Server=$ServerInstance;Database=$Database;Integrated Security=true;TrustServerCertificate=true;Pooling=false"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " CONCURRENCY TEST: VENUE MAP RACE GUARD" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$fail = 0
function Check($name, $ok, $detail = "") {
    if ($ok) { Write-Host "[PASS] $name" -ForegroundColor Green }
    else     { Write-Host "[FAIL] $name $detail" -ForegroundColor Red; $script:fail++ }
}

function Exec-Scalar($conn, $sql, $timeoutSec) {
    $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.CommandTimeout = $timeoutSec
    return $cmd.ExecuteScalar()
}

function Run-OneCase($caseLabel, $updateSql, $expectedErrorFragment) {
    $c0 = New-Object System.Data.SqlClient.SqlConnection $cs
    $c0.Open()
    Exec-Scalar $c0 "DELETE FROM Zone WHERE ZoneCode LIKE 'CONC14-%'; DELETE FROM Venue WHERE VenueName = N'ConcurrencyTest14';" 30 | Out-Null
    $adminId = Exec-Scalar $c0 "SELECT TOP 1 ua.UserID FROM UserAccount ua JOIN UserRoleAssignment ura ON ura.UserID=ua.UserID JOIN Role r ON r.RoleID=ura.RoleID WHERE r.RoleName='Admin' AND ura.AssignmentStatus='Active' AND ua.AccountStatus='Active'" 30
    if (-not $adminId) { Check "$caseLabel - setup" $false "khong tim thay Admin de test"; $c0.Close(); return }

    $cmdV = $c0.CreateCommand()
    $cmdV.CommandText = "DECLARE @v INT; EXEC sp_CreateVenue @ActorUserID=@a, @VenueName=N'ConcurrencyTest14', @Address=N'x', @NewVenueID=@v OUTPUT; SELECT @v;"
    $cmdV.Parameters.AddWithValue("@a", $adminId) | Out-Null
    $venueId = $cmdV.ExecuteScalar()
    Exec-Scalar $c0 "EXEC sp_ConfigureVenueMap @ActorUserID=$adminId, @VenueID=$venueId, @MapWidth=1000, @MapHeight=1000;" 30 | Out-Null

    # Zone san co tai vi tri an toan - dung cho truong hop UpdateZone (di chuyen zone da co).
    $cmdZ = $c0.CreateCommand()
    $cmdZ.CommandText = "DECLARE @z INT; EXEC sp_CreateZone @ActorUserID=$adminId, @VenueID=$venueId, @ZoneCode='CONC14-EXIST', @ZoneName=N'x', @ZoneX=10, @ZoneY=10, @ZoneWidth=50, @ZoneHeight=50, @NewZoneID=@z OUTPUT; SELECT @z;"
    $existingZoneId = $cmdZ.ExecuteScalar()
    $c0.Close()

    # --- Connection A: tu giu UPDLOCK tren dong Venue (mo phong buoc dau cua
    #     sp_ConfigureVenueMap), giu 4 giay, roi GHI gia tri map moi (500x500) va COMMIT.
    $connA = New-Object System.Data.SqlClient.SqlConnection $cs
    $connA.Open()
    $spidA = Exec-Scalar $connA "SELECT @@SPID" 5
    $cmdA = $connA.CreateCommand()
    $cmdA.CommandText = @"
BEGIN TRAN;
DECLARE @dummy INT;
SELECT @dummy = MapWidth FROM Venue WITH (UPDLOCK) WHERE VenueID = $venueId;
WAITFOR DELAY '00:00:04';
UPDATE Venue SET MapWidth = 500, MapHeight = 500 WHERE VenueID = $venueId;
COMMIT TRAN;
"@
    $cmdA.CommandTimeout = 30
    $iar = $cmdA.BeginExecuteNonQuery()

    # Cho toi khi A that su dang giu khoa (server-side, khong doan bang sleep).
    $connMon = New-Object System.Data.SqlClient.SqlConnection $cs
    $connMon.Open()
    $locked = $false
    $waited = 0
    while (-not $locked -and $waited -lt 5000) {
        $cnt = Exec-Scalar $connMon "SELECT COUNT(*) FROM sys.dm_tran_locks WHERE request_session_id=$spidA AND resource_type='KEY' AND request_mode='U'" 5
        if ([int]$cnt -ge 1) { $locked = $true; break }
        Start-Sleep -Milliseconds 30
        $waited += 30
    }
    Check "$caseLabel - A that su dang giu UPDLOCK tren Venue (DMV)" $locked "(cho $waited ms)"

    if ($locked) {
        # --- Connection B: goi thu tuc THAT (khong sua doi), phai BI KHOA cho toi khi A nha khoa. ---
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $connB = New-Object System.Data.SqlClient.SqlConnection $cs
        $connB.Open()
        $cmdB = $connB.CreateCommand()
        $cmdB.CommandText = $updateSql -f $adminId, $venueId, $existingZoneId
        $cmdB.CommandTimeout = 30
        $errMsg = $null
        try { $cmdB.ExecuteNonQuery() | Out-Null } catch { $errMsg = $_.Exception.Message }
        $sw.Stop()
        $connB.Close()

        # B phai mat GAN 4 giay (bi khoa cho A xong) - neu B tra ve gan nhu ngay
        # lap tuc (<1s) thi UPDLOCK khong con tac dung, tuc fix da bi go/hong.
        Check "$caseLabel - B bi khoa cho toi khi A nha khoa (mat >= 3s)" ($sw.Elapsed.TotalSeconds -ge 3) `
              "(thuc te: $([math]::Round($sw.Elapsed.TotalSeconds,2))s)"

        Check "$caseLabel - B doc duoc gia tri MOI va tu choi dung loi" `
              ($errMsg -ne $null -and $errMsg -like "*$expectedErrorFragment*") "(loi thuc te: $errMsg)"
    }

    try { $cmdA.EndExecuteNonQuery($iar) | Out-Null } catch {}
    $connA.Close()
    $connMon.Close()

    # --- Kiem tra CUOI CUNG: bat bien phai giu nguyen - khong Zone nao vuot bien. ---
    $c1 = New-Object System.Data.SqlClient.SqlConnection $cs
    $c1.Open()
    $violation = Exec-Scalar $c1 @"
SELECT COUNT(*) FROM Venue v JOIN Zone z ON z.VenueID = v.VenueID
WHERE v.VenueID = $venueId AND z.ZoneX IS NOT NULL
  AND (z.ZoneX + z.ZoneWidth > v.MapWidth OR z.ZoneY + z.ZoneHeight > v.MapHeight);
"@ 10
    Check "$caseLabel - khong Zone nao vuot bien Venue map sau cung" ([int]$violation -eq 0) "(so vi pham: $violation)"
    Exec-Scalar $c1 "DELETE FROM Zone WHERE VenueID=$venueId; DELETE FROM Venue WHERE VenueID=$venueId;" 10 | Out-Null
    $c1.Close()
}

# Truong hop 1: sp_CreateZone tao khu MOI trong luc mat phang dang bi thu nho.
Run-OneCase "sp_CreateZone" `
    "DECLARE @z INT; EXEC sp_CreateZone @ActorUserID={0}, @VenueID={1}, @ZoneCode='CONC14-NEW', @ZoneName=N'x', @ZoneX=800, @ZoneY=800, @ZoneWidth=100, @ZoneHeight=100, @NewZoneID=@z OUTPUT" `
    "mat phang cua dia diem"

# Truong hop 2: sp_UpdateZone DI CHUYEN khu da co trong luc mat phang dang bi thu nho.
Run-OneCase "sp_UpdateZone" `
    "EXEC sp_UpdateZone @ActorUserID={0}, @ZoneID={2}, @ZoneX=800, @ZoneY=800, @ZoneWidth=100, @ZoneHeight=100" `
    "mat phang cua dia diem"

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
if ($fail -eq 0) {
    Write-Host "[PASS] Fix chan dung tranh chap dong thoi cho ca sp_CreateZone va sp_UpdateZone." -ForegroundColor Green
} else {
    Write-Host "[FAIL] $fail kiem tra that bai - xem chi tiet o tren." -ForegroundColor Red
}
