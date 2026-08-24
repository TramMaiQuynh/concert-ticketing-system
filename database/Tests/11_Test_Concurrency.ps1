# ====================================================================
# 11_Test_Concurrency.ps1
# Test Oversell (Lost Update Guard) for sp_CreateBooking
# ====================================================================

param (
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$Database = "ConcertTicketingDB",
    [int]$Threads = 20
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " CONCURRENCY TEST: OVERSELL GUARD" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Prepare data: Make sure EventSeat 5 is Available
$prepSql = "
USE ConcertTicketingDB;
UPDATE EventSeat SET InventoryStatus = 'Available' WHERE EventSeatID = 5;
"
Invoke-Sqlcmd -ServerInstance $ServerInstance -Database $Database -Query $prepSql

Write-Host "Starting $Threads parallel sessions to book EventSeatID = 5 simultaneously..." -ForegroundColor Yellow

$scriptBlock = {
    param($ServerInstance, $Database, $ThreadId)
    $connStr = "Server=$ServerInstance;Database=$Database;Integrated Security=True;Pooling=False;"
    $sql = "
    SET QUOTED_IDENTIFIER ON;
    DECLARE @Seats dbo.EventSeatListType;
    INSERT INTO @Seats VALUES (5);
    EXEC sp_CreateBooking @CustomerUserID = 3, @ConcertID = 1, @SeatList = @Seats;
    "
    try {
        $conn = New-Object System.Data.SqlClient.SqlConnection($connStr)
        $conn.Open()
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = $sql
        $cmd.ExecuteNonQuery() | Out-Null
        $conn.Close()
        return "Thread $ThreadId : SUCCESS"
    }
    catch {
        return "Thread $ThreadId : FAILED - $($_.Exception.Message)"
    }
}

$runspaces = @()
for ($i = 1; $i -le $Threads; $i++) {
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript($scriptBlock).AddArgument($ServerInstance).AddArgument($Database).AddArgument($i)
    $runspaces += [PSCustomObject]@{ PS = $ps; Async = $ps.BeginInvoke() }
}

$results = @()
foreach ($rs in $runspaces) {
    $results += $rs.PS.EndInvoke($rs.Async)
    $rs.PS.Dispose()
}

$successCount = ($results | Where-Object { $_ -match "SUCCESS" }).Count
$failCount = ($results | Where-Object { $_ -match "FAILED" }).Count

Write-Host "
RESULTS:" -ForegroundColor Cyan
$results | ForEach-Object { 
    if ($_ -match "SUCCESS") { Write-Host $_ -ForegroundColor Green }
    else { Write-Host $_ -ForegroundColor Red }
}

Write-Host "
SUMMARY:" -ForegroundColor Cyan
Write-Host "Total Threads : $Threads"
Write-Host "Success (Expected 1) : $successCount"
Write-Host "Failed (Expected $($Threads-1)) : $failCount"

if ($successCount -eq 1) {
    Write-Host "
[PASS] Database successfully prevented oversell! Only 1 booking was created." -ForegroundColor Green
} else {
    Write-Host "
[FAIL] Concurrency failure! $successCount bookings were created." -ForegroundColor Red
}
