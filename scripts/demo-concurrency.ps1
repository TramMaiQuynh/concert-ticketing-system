<#
.SYNOPSIS
    Trình diễn 5 hiện tượng tranh chấp đồng thời trên chính hệ thống này.

.DESCRIPTION
    Mỗi hiện tượng được trình diễn theo HAI VẾ, vì chỉ một vế thì không chứng minh
    được gì:

      VẾ 1 — hiện tượng CÓ THẬT: chạy theo cách làm ngây thơ (hoặc gỡ bỏ lớp bảo vệ)
             để người xem thấy lỗi thực sự xảy ra.
      VẾ 2 — hệ thống CHẶN được: chạy đúng cơ chế mà hệ thống đang dùng, cho thấy
             kết quả khác hẳn.

    Cửa sổ tranh chấp được nới rộng bằng WAITFOR, nên kết quả TÁI HIỆN ĐƯỢC mọi lần
    chứ không phụ thuộc may rủi về thời điểm. Đây là điều kiện bắt buộc để dám trình
    diễn trước hội đồng.

    Kịch bản tự dựng dữ liệu riêng (tiền tố DEMO-CC) nên chạy được bất kể đã nạp
    dữ liệu demo hay chưa, và không đụng vào dữ liệu của phần trình diễn tính năng.

.PARAMETER Scenario
    lost-update | dirty-read | non-repeatable | phantom | deadlock | all

.EXAMPLE
    .\scripts\demo-concurrency.ps1 -Scenario all
    .\scripts\demo-concurrency.ps1 -Scenario lost-update
#>
param(
    [ValidateSet('lost-update','dirty-read','non-repeatable','phantom','deadlock','all')]
    [string]$Scenario = 'all',
    [string]$ServerInstance = ".\SQLEXPRESS",
    [string]$DatabaseName   = "ConcertTicketingDB"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$TmpDir = Join-Path $PSScriptRoot ".cc-tmp"
if (-not (Test-Path $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null }

function Write-Title($text) {
    Write-Host ""
    Write-Host ("=" * 72) -ForegroundColor Cyan
    Write-Host "  $text" -ForegroundColor Cyan
    Write-Host ("=" * 72) -ForegroundColor Cyan
}
function Write-Part($text)  { Write-Host ""; Write-Host "  $text" -ForegroundColor Yellow }
function Write-User($text)  { Write-Host "     [Người dùng thấy] $text" -ForegroundColor White }
function Write-Bad($text)   { Write-Host "     $text" -ForegroundColor Red }
function Write-Good($text)  { Write-Host "     $text" -ForegroundColor Green }

# sqlcmd -I là BẮT BUỘC: các bảng có filtered index, thiếu QUOTED_IDENTIFIER ON thì
# mọi lệnh ghi đều bị từ chối bằng lỗi 1934 rất khó hiểu.
function Invoke-Sql([string]$Sql) {
    $f = Join-Path $TmpDir ("q_" + [Guid]::NewGuid().ToString("N") + ".sql")
    Set-Content -Path $f -Value $Sql -Encoding UTF8
    $out = & sqlcmd -S $ServerInstance -d $DatabaseName -E -I -h -1 -W -i $f 2>&1
    Remove-Item $f -Force -ErrorAction SilentlyContinue
    return ($out | Where-Object { $_ -notmatch '^Warning:' -and $_ -notmatch '^\s*$' })
}

# Chạy HAI phiên chồng lấn nhau. Phiên A khởi động trước $DelayB giây để bảo đảm
# A vào vùng tranh chấp trước, nhờ đó kết quả xác định chứ không ngẫu nhiên.
function Invoke-TwoSession([string]$SqlA, [string]$SqlB, [int]$DelayB = 1) {
    $fA = Join-Path $TmpDir "sessA.sql"; $fB = Join-Path $TmpDir "sessB.sql"
    $oA = Join-Path $TmpDir "outA.txt";  $oB = Join-Path $TmpDir "outB.txt"
    Set-Content -Path $fA -Value $SqlA -Encoding UTF8
    Set-Content -Path $fB -Value $SqlB -Encoding UTF8

    $pA = Start-Process -FilePath "sqlcmd" -NoNewWindow -PassThru `
            -ArgumentList @("-S",$ServerInstance,"-d",$DatabaseName,"-E","-I","-h","-1","-W","-i",$fA) `
            -RedirectStandardOutput $oA
    Start-Sleep -Seconds $DelayB
    $pB = Start-Process -FilePath "sqlcmd" -NoNewWindow -PassThru `
            -ArgumentList @("-S",$ServerInstance,"-d",$DatabaseName,"-E","-I","-h","-1","-W","-i",$fB) `
            -RedirectStandardOutput $oB
    $pA.WaitForExit(); $pB.WaitForExit()

    $rA = @(); $rB = @()
    if (Test-Path $oA) { $rA = @(Get-Content $oA | Where-Object { $_ -notmatch '^Warning:' -and $_ -notmatch '^\s*$' }) }
    if (Test-Path $oB) { $rB = @(Get-Content $oB | Where-Object { $_ -notmatch '^Warning:' -and $_ -notmatch '^\s*$' }) }
    return @{ A = $rA; B = $rB }
}

# ── Dựng dữ liệu riêng cho phần trình diễn ──────────────────────────────────
function Initialize-DemoData {
    Write-Host "  Đang dựng dữ liệu trình diễn (tiền tố DEMO-CC)..." -ForegroundColor DarkGray
    $ids = Invoke-Sql @"
SET NOCOUNT ON;
DECLARE @sys INT = (SELECT UserID FROM UserAccount WHERE Username='system');
EXEC sp_set_session_context @key=N'UserID', @value=@sys;

IF NOT EXISTS (SELECT 1 FROM UserAccount WHERE Username='cc_khach_A')
    INSERT INTO UserAccount (Username,AccountStatus,Email,DisplayName)
    VALUES ('cc_khach_A','Active','a@cc.demo',N'Khách A'),
           ('cc_khach_B','Active','b@cc.demo',N'Khách B'),
           ('cc_bantochuc','Active','o@cc.demo',N'Ban tổ chức');

DECLARE @A INT=(SELECT UserID FROM UserAccount WHERE Username='cc_khach_A');
DECLARE @B INT=(SELECT UserID FROM UserAccount WHERE Username='cc_khach_B');
DECLARE @O INT=(SELECT UserID FROM UserAccount WHERE Username='cc_bantochuc');

IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID=ura.RoleID WHERE ura.UserID=@A AND r.RoleName='Customer')
BEGIN
    INSERT INTO UserRoleAssignment (UserID,RoleID,AssignmentStatus) SELECT @A,RoleID,'Active' FROM Role WHERE RoleName='Customer';
    INSERT INTO UserRoleAssignment (UserID,RoleID,AssignmentStatus) SELECT @B,RoleID,'Active' FROM Role WHERE RoleName='Customer';
END

DECLARE @cid INT = (SELECT ConcertID FROM Concert WHERE ConcertName=N'DEMO-CC-Concert');
IF @cid IS NULL
BEGIN
    INSERT INTO Venue (VenueName,VenueStatus) VALUES (N'DEMO-CC-Venue','Active');
    DECLARE @v INT=SCOPE_IDENTITY();
    INSERT INTO Zone (VenueID,ZoneCode,ZoneName,ZoneType) VALUES (@v,'CC',N'DEMO-CC-Zone','Seated');
    DECLARE @z INT=SCOPE_IDENTITY();
    INSERT INTO Seat (ZoneID,VenueID,SeatCode,SeatLabel) VALUES (@z,@v,'CC-A01','A01');
    DECLARE @s1 INT=SCOPE_IDENTITY();
    INSERT INTO Seat (ZoneID,VenueID,SeatCode,SeatLabel) VALUES (@z,@v,'CC-A02','A02');
    DECLARE @s2 INT=SCOPE_IDENTITY();
    INSERT INTO Artist (ArtistName,ArtistStatus) VALUES (N'DEMO-CC-Artist','Active');
    DECLARE @ar INT=SCOPE_IDENTITY();

    INSERT INTO Concert (OrganizerUserID,ArtistID,VenueID,ConcertName,ConcertStatus,
                         StartDatetime,EndDatetime,SaleStartDatetime,SaleEndDatetime,
                         PurchaseLimit,TemporaryHoldDuration,FairAccessEnabled,WaitlistEnabled,SalesPaused)
    VALUES (@O,@ar,@v,N'DEMO-CC-Concert','Draft',
            DATEADD(DAY,30,SYSDATETIME()),DATEADD(DAY,30,DATEADD(HOUR,3,SYSDATETIME())),
            DATEADD(DAY,-1,SYSDATETIME()),DATEADD(DAY,29,SYSDATETIME()),
            4,900,0,0,0);
    SET @cid=SCOPE_IDENTITY();
    INSERT INTO TicketCategory (ConcertID,CategoryName,BasePrice,CategoryStatus) VALUES (@cid,N'DEMO-CC-Hang',500000,'Active');
    DECLARE @cat INT=SCOPE_IDENTITY();
    INSERT INTO EventSeat (ConcertID,SeatID,TicketCategoryID,InventoryStatus,SalePrice) VALUES (@cid,@s1,@cat,'Available',500000);
    INSERT INTO EventSeat (ConcertID,SeatID,TicketCategoryID,InventoryStatus,SalePrice) VALUES (@cid,@s2,@cat,'Available',500000);
    INSERT INTO Queue (ConcertID,QueueStatus,AdmissionCapacity,FairAccessPolicy) VALUES (@cid,'Open',100,'FIFO');
    UPDATE Concert SET ConcertStatus='Published' WHERE ConcertID=@cid;
    UPDATE Concert SET ConcertStatus='OnSale'    WHERE ConcertID=@cid;
END

SELECT CAST(@cid AS VARCHAR)+'|'
     +CAST((SELECT MIN(EventSeatID) FROM EventSeat WHERE ConcertID=@cid) AS VARCHAR)+'|'
     +CAST(@A AS VARCHAR)+'|'+CAST(@B AS VARCHAR)+'|'
     +CAST((SELECT QueueID FROM Queue WHERE ConcertID=@cid) AS VARCHAR);
"@
    $line = ($ids | Where-Object { $_ -match '^\d+\|' } | Select-Object -First 1)
    if (-not $line) { throw "Không dựng được dữ liệu trình diễn. Kiểm tra database đã deploy chưa." }
    $p = $line.Split('|')
    return @{ ConcertId = $p[0]; SeatId = $p[1]; CustA = $p[2]; CustB = $p[3]; QueueId = $p[4] }
}

function Reset-Seat($d) {
    Invoke-Sql @"
SET NOCOUNT ON;
DECLARE @sys INT=(SELECT UserID FROM UserAccount WHERE Username='system');
EXEC sp_set_session_context @key=N'UserID',@value=@sys;
DELETE FROM BookingEventSeatAllocation WHERE BookingID IN (SELECT BookingID FROM Booking WHERE ConcertID=$($d.ConcertId));
DELETE FROM Booking WHERE ConcertID=$($d.ConcertId);
UPDATE EventSeat SET InventoryStatus='Available' WHERE ConcertID=$($d.ConcertId);
DELETE FROM QueueEntry WHERE QueueID=$($d.QueueId);
"@ | Out-Null
}

# ════════════════════════════════════════════════════════════════════════════
# 1. LOST UPDATE  (bán vượt ghế)
# ════════════════════════════════════════════════════════════════════════════
function Show-LostUpdate($d) {
    Write-Title "1. LOST UPDATE — hai khách cùng mua một ghế"
    Write-Host "  Bối cảnh: ghế A01 đang trống. Khách A và khách B cùng bấm 'Giữ chỗ' đúng một lúc."

    Reset-Seat $d
    Write-Part "VẾ 1 — Nếu viết theo cách ngây thơ (đọc trạng thái rồi mới ghi):"
    $naiveA = @"
SET NOCOUNT ON;
BEGIN TRANSACTION;
DECLARE @st VARCHAR(32);
SELECT @st=InventoryStatus FROM EventSeat WHERE EventSeatID=$($d.SeatId);
PRINT 'A: he thong bao ghe dang [' + @st + '] -> cho phep A giu cho';
WAITFOR DELAY '00:00:04';
UPDATE EventSeat SET InventoryStatus='OnHold' WHERE EventSeatID=$($d.SeatId);
PRINT 'A: da giu cho THANH CONG';
COMMIT TRANSACTION;
"@
    $naiveB = @"
SET NOCOUNT ON;
BEGIN TRANSACTION;
DECLARE @st VARCHAR(32);
SELECT @st=InventoryStatus FROM EventSeat WHERE EventSeatID=$($d.SeatId);
PRINT 'B: he thong bao ghe dang [' + @st + '] -> cho phep B giu cho';
WAITFOR DELAY '00:00:05';
UPDATE EventSeat SET InventoryStatus='OnHold' WHERE EventSeatID=$($d.SeatId);
PRINT 'B: da giu cho THANH CONG';
COMMIT TRANSACTION;
"@
    $r = Invoke-TwoSession $naiveA $naiveB 1
    $r.A | ForEach-Object { Write-User $_ }
    $r.B | ForEach-Object { Write-User $_ }
    Write-Bad ">>> CẢ HAI khách đều tin mình đã giữ được ghế A01. Một ghế bán cho hai người."

    Reset-Seat $d
    Write-Part "VẾ 2 — Hệ thống thật (sp_CreateBooking, cập nhật có điều kiện + kiểm số dòng):"
    $realA = @"
SET NOCOUNT ON;
DECLARE @b INT;
BEGIN TRY
    EXEC dbo.sp_CreateBooking @CustomerUserID=$($d.CustA), @ConcertID=$($d.ConcertId), @SeatList='$($d.SeatId)', @NewBookingID=@b OUTPUT;
    PRINT 'Khach A: Giu cho thanh cong, ma don BKG-' + CAST(@b AS VARCHAR);
END TRY
BEGIN CATCH
    PRINT 'Khach A: ' + ERROR_MESSAGE();
END CATCH
"@
    $realB = @"
SET NOCOUNT ON;
DECLARE @b INT;
BEGIN TRY
    EXEC dbo.sp_CreateBooking @CustomerUserID=$($d.CustB), @ConcertID=$($d.ConcertId), @SeatList='$($d.SeatId)', @NewBookingID=@b OUTPUT;
    PRINT 'Khach B: Giu cho thanh cong, ma don BKG-' + CAST(@b AS VARCHAR);
END TRY
BEGIN CATCH
    PRINT 'Khach B: ' + ERROR_MESSAGE();
END CATCH
"@
    $r = Invoke-TwoSession $realA $realB 0
    $r.A | ForEach-Object { Write-User $_ }
    $r.B | ForEach-Object { Write-User $_ }
    $cnt = (Invoke-Sql "SET NOCOUNT ON; SELECT COUNT(*) FROM BookingEventSeatAllocation WHERE EventSeatID=$($d.SeatId) AND AllocationStatus='Active';" | Select-Object -First 1).Trim()
    Write-Good ">>> Đúng MỘT khách giữ được ghế; người kia bị từ chối ngay. Số đơn đang giữ ghế A01 = $cnt"
    Reset-Seat $d
}

# ════════════════════════════════════════════════════════════════════════════
# 2. DIRTY READ  (đọc dữ liệu chưa cam kết)
# ════════════════════════════════════════════════════════════════════════════
function Show-DirtyRead($d) {
    Write-Title "2. DIRTY READ — nhìn thấy thứ chưa hề xảy ra"
    Write-Host "  Bối cảnh: khách A bấm giữ chỗ nhưng giao dịch bị hủy giữa chừng."
    Write-Host "  Đúng lúc đó khách B mở sơ đồ ghế để xem."
    Reset-Seat $d

    $sqlA = @"
SET NOCOUNT ON;
BEGIN TRANSACTION;
UPDATE EventSeat SET InventoryStatus='OnHold' WHERE EventSeatID=$($d.SeatId);
PRINT 'A: dang giu cho (CHUA xac nhan)';
WAITFOR DELAY '00:00:04';
ROLLBACK TRANSACTION;
PRINT 'A: giao dich BI HUY -> thuc te ghe VAN CON TRONG';
"@
    $sqlB = @"
SET NOCOUNT ON;
DECLARE @ban VARCHAR(32), @sach VARCHAR(32);
SELECT @ban = InventoryStatus FROM EventSeat WITH (NOLOCK) WHERE EventSeatID=$($d.SeatId);
PRINT 'B [neu he thong dung NOLOCK]: so do bao ghe dang [' + @ban + ']';
SELECT @sach = InventoryStatus FROM EventSeat WHERE EventSeatID=$($d.SeatId);
PRINT 'B [he thong that - READ COMMITTED]: so do bao ghe dang [' + @sach + ']';
"@
    $r = Invoke-TwoSession $sqlA $sqlB 1
    $r.A | ForEach-Object { Write-User $_ }
    $r.B | ForEach-Object { Write-User $_ }
    Write-Bad ">>> Với NOLOCK: khách B bị báo ghế đã có người giữ, nên bỏ đi — trong khi ghế thật sự vẫn trống."
    Write-Good ">>> Hệ thống thật: khách B phải chờ tới khi A dứt khoát, rồi thấy đúng trạng thái [Available]."
    Reset-Seat $d
}

# ════════════════════════════════════════════════════════════════════════════
# 3. NON-REPEATABLE READ  (đọc lại thì giá trị đã khác)
# ════════════════════════════════════════════════════════════════════════════
function Show-NonRepeatable($d) {
    Write-Title "3. NON-REPEATABLE READ — cùng một việc, đọc hai lần ra hai kết quả"
    Write-Host "  Bối cảnh: trong MỘT lượt xử lý, hệ thống đọc trạng thái ghế hai lần"
    Write-Host "  (lần đầu để kiểm tra, lần sau để ghi nhận). Giữa hai lần đó có người khác chen vào."
    Reset-Seat $d

    $plainA = @"
SET NOCOUNT ON;
BEGIN TRANSACTION;
DECLARE @l1 VARCHAR(32), @l2 VARCHAR(32);
SELECT @l1=InventoryStatus FROM EventSeat WHERE EventSeatID=$($d.SeatId);
PRINT 'Lan doc 1: ghe dang [' + @l1 + ']';
WAITFOR DELAY '00:00:04';
SELECT @l2=InventoryStatus FROM EventSeat WHERE EventSeatID=$($d.SeatId);
PRINT 'Lan doc 2: ghe dang [' + @l2 + ']';
IF @l1 <> @l2 PRINT '>>> HAI LAN DOC KHAC NHAU';
ELSE PRINT '>>> Hai lan doc GIONG NHAU';
COMMIT TRANSACTION;
"@
    $writerB = @"
SET NOCOUNT ON;
UPDATE EventSeat SET InventoryStatus='OnHold' WHERE EventSeatID=$($d.SeatId);
PRINT 'Nguoi khac vua giu mat ghe do va da xac nhan xong';
"@
    Write-Part "VẾ 1 — Đọc trần (không đặt khoá):"
    $r = Invoke-TwoSession $plainA $writerB 1
    $r.B | ForEach-Object { Write-User $_ }
    $r.A | ForEach-Object { Write-User $_ }
    Write-Bad ">>> Dữ liệu đổi ngay giữa lượt xử lý: quyết định dựa trên lần đọc 1 đã sai."

    Reset-Seat $d
    Write-Part "VẾ 2 — Đúng cơ chế hệ thống dùng (WITH UPDLOCK, như sp_CheckInTicket / sp_CreateBooking):"
    $lockA = $plainA.Replace("FROM EventSeat WHERE","FROM EventSeat WITH (UPDLOCK) WHERE")
    $r = Invoke-TwoSession $lockA $writerB 1
    $r.A | ForEach-Object { Write-User $_ }
    $r.B | ForEach-Object { Write-User $_ }
    Write-Good ">>> Người khác bị giữ lại tới khi lượt xử lý xong; hai lần đọc giống hệt nhau."
    Reset-Seat $d
}

# ════════════════════════════════════════════════════════════════════════════
# 4. PHANTOM READ  (đếm lại thì mọc thêm dòng)
# ════════════════════════════════════════════════════════════════════════════
function Show-Phantom($d) {
    Write-Title "4. PHANTOM READ — đếm lại thì tự nhiên mọc thêm người"
    Write-Host "  Bối cảnh: hệ thống đếm số người trong hàng đợi để cấp suất vào mua."
    Write-Host "  Giữa hai lần đếm, có người mới xếp hàng."
    Reset-Seat $d

    $plainA = @"
SET NOCOUNT ON;
BEGIN TRANSACTION;
DECLARE @n1 INT, @n2 INT;
SELECT @n1=COUNT(*) FROM QueueEntry WHERE QueueID=$($d.QueueId);
PRINT 'Dem lan 1: hang doi co ' + CAST(@n1 AS VARCHAR) + ' nguoi';
WAITFOR DELAY '00:00:04';
SELECT @n2=COUNT(*) FROM QueueEntry WHERE QueueID=$($d.QueueId);
PRINT 'Dem lan 2: hang doi co ' + CAST(@n2 AS VARCHAR) + ' nguoi';
IF @n1 <> @n2 PRINT '>>> XUAT HIEN NGUOI MOI giua hai lan dem';
ELSE PRINT '>>> Hai lan dem GIONG NHAU';
COMMIT TRANSACTION;
"@
    $joinB = @"
SET NOCOUNT ON;
INSERT INTO QueueEntry (QueueID,CustomerUserID,JoinedTimestamp,AdmissionPosition,QueueStatus)
VALUES ($($d.QueueId),$($d.CustB),SYSDATETIME(),1,'Waiting');
PRINT 'Mot khach vua xep hang xong';
"@
    Write-Part "VẾ 1 — Đếm trần (không đặt khoá phạm vi):"
    $r = Invoke-TwoSession $plainA $joinB 1
    $r.B | ForEach-Object { Write-User $_ }
    $r.A | ForEach-Object { Write-User $_ }
    Write-Bad ">>> Suất vào mua có thể bị cấp vượt, vì con số dùng để quyết định đã cũ."

    Reset-Seat $d
    Write-Part "VẾ 2 — Đúng cơ chế hệ thống dùng (WITH UPDLOCK, HOLDLOCK — như sp_JoinQueue / sp_JoinWaitlist):"
    $lockA = $plainA.Replace("FROM QueueEntry WHERE","FROM QueueEntry WITH (UPDLOCK, HOLDLOCK) WHERE")
    $r = Invoke-TwoSession $lockA $joinB 1
    $r.A | ForEach-Object { Write-User $_ }
    $r.B | ForEach-Object { Write-User $_ }
    Write-Good ">>> Khoá phạm vi giữ cả khoảng trống, người mới phải chờ; hai lần đếm giống nhau."
    Reset-Seat $d
}

# ════════════════════════════════════════════════════════════════════════════
# 5. DEADLOCK  (hai bên chờ nhau)
# ════════════════════════════════════════════════════════════════════════════
function Show-Deadlock($d) {
    Write-Title "5. DEADLOCK — hai giao dịch chờ khoá của nhau"
    Reset-Seat $d
    $seat2 = (Invoke-Sql "SET NOCOUNT ON; SELECT MAX(EventSeatID) FROM EventSeat WHERE ConcertID=$($d.ConcertId);" | Select-Object -First 1).Trim()

    Write-Part "VẾ 1 — Dựng đúng vòng chờ: A khoá ghế 1 rồi xin ghế 2, B khoá ghế 2 rồi xin ghế 1"
    $dlA = @"
SET NOCOUNT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE EventSeat SET SalePrice=SalePrice WHERE EventSeatID=$($d.SeatId);
    PRINT 'A: da khoa ghe A01, dang xin them ghe A02...';
    WAITFOR DELAY '00:00:02';
    UPDATE EventSeat SET SalePrice=SalePrice WHERE EventSeatID=$seat2;
    COMMIT TRANSACTION;
    PRINT 'A: hoan tat';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
    PRINT 'A: bi huy - loi ' + CAST(ERROR_NUMBER() AS VARCHAR);
END CATCH
"@
    $dlB = @"
SET NOCOUNT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    UPDATE EventSeat SET SalePrice=SalePrice WHERE EventSeatID=$seat2;
    PRINT 'B: da khoa ghe A02, dang xin them ghe A01...';
    WAITFOR DELAY '00:00:02';
    UPDATE EventSeat SET SalePrice=SalePrice WHERE EventSeatID=$($d.SeatId);
    COMMIT TRANSACTION;
    PRINT 'B: hoan tat';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT>0 ROLLBACK TRANSACTION;
    PRINT 'B: bi huy - loi ' + CAST(ERROR_NUMBER() AS VARCHAR) + ' (1205 = bi chon lam nan nhan deadlock)';
END CATCH
"@
    $r = Invoke-TwoSession $dlA $dlB 0
    $r.A | ForEach-Object { Write-User $_ }
    $r.B | ForEach-Object { Write-User $_ }
    Write-Bad ">>> SQL Server phát hiện vòng chờ, chọn một bên làm nạn nhân (lỗi 1205) và hủy giao dịch đó."
    Write-Host "     Bên còn lại đi tiếp bình thường; bên bị hủy được rollback trọn vẹn, không mất dữ liệu." -ForegroundColor DarkGray

    Reset-Seat $d
    Write-Part "VẾ 2 — Luồng đặt vé thật: hai khách chọn CHỒNG ghế theo thứ tự NGƯỢC nhau"
    $bkA = @"
SET NOCOUNT ON;
DECLARE @b INT;
BEGIN TRY
    EXEC dbo.sp_CreateBooking @CustomerUserID=$($d.CustA), @ConcertID=$($d.ConcertId), @SeatList='$($d.SeatId),$seat2', @NewBookingID=@b OUTPUT;
    PRINT 'Khach A (chon A01 roi A02): dat thanh cong';
END TRY
BEGIN CATCH
    PRINT 'Khach A: loi ' + CAST(ERROR_NUMBER() AS VARCHAR) + ' - ' + ERROR_MESSAGE();
END CATCH
"@
    $bkB = @"
SET NOCOUNT ON;
DECLARE @b INT;
BEGIN TRY
    EXEC dbo.sp_CreateBooking @CustomerUserID=$($d.CustB), @ConcertID=$($d.ConcertId), @SeatList='$seat2,$($d.SeatId)', @NewBookingID=@b OUTPUT;
    PRINT 'Khach B (chon A02 roi A01): dat thanh cong';
END TRY
BEGIN CATCH
    PRINT 'Khach B: loi ' + CAST(ERROR_NUMBER() AS VARCHAR) + ' - ' + ERROR_MESSAGE();
END CATCH
"@
    $r = Invoke-TwoSession $bkA $bkB 0
    $r.A | ForEach-Object { Write-User $_ }
    $r.B | ForEach-Object { Write-User $_ }
    Write-Good ">>> KHÔNG deadlock. sp_CreateBooking giữ ghế bằng MỘT câu lệnh tập hợp duy nhất,"
    Write-Host "     nên SQL Server luôn khoá theo thứ tự chỉ mục, không theo thứ tự khách chọn." -ForegroundColor Green
    Write-Host "     Hai giao dịch xin khoá cùng chiều thì không thể tạo thành vòng chờ." -ForegroundColor Green
    Reset-Seat $d
}

# ── Chạy ────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  TRÌNH DIỄN CÁC HIỆN TƯỢNG TRANH CHẤP ĐỒNG THỜI" -ForegroundColor Magenta
Write-Host "  Mỗi hiện tượng gồm hai vế: lỗi CÓ THẬT, và hệ thống CHẶN được." -ForegroundColor DarkGray

$data = Initialize-DemoData

switch ($Scenario) {
    'lost-update'    { Show-LostUpdate   $data }
    'dirty-read'     { Show-DirtyRead    $data }
    'non-repeatable' { Show-NonRepeatable $data }
    'phantom'        { Show-Phantom      $data }
    'deadlock'       { Show-Deadlock     $data }
    'all' {
        Show-LostUpdate    $data
        Show-DirtyRead     $data
        Show-NonRepeatable $data
        Show-Phantom       $data
        Show-Deadlock      $data
    }
}

Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("=" * 72) -ForegroundColor Magenta
Write-Host "  KẾT THÚC TRÌNH DIỄN" -ForegroundColor Magenta
Write-Host ("=" * 72) -ForegroundColor Magenta
Write-Host ""
Write-Host "  Dữ liệu trình diễn mang tiền tố DEMO-CC, tách khỏi dữ liệu demo tính năng." -ForegroundColor DarkGray
Write-Host "  Muốn trả database về hoàn toàn sạch:" -ForegroundColor DarkGray
Write-Host "     cd database; .\deploy.ps1 -DropExisting `$true" -ForegroundColor DarkGray
Write-Host ""
