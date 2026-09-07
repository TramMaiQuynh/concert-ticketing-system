-- ============================================================
-- 12_Test_SP_AdminAndCatalog.sql
-- Test cac SP truoc day KHONG co test nao:
--   sp_AdminUpdateUserStatus (UAI01, UAI02)
--   sp_AssignRole            (UAI01)
--   sp_AddEventSeats         (precondition BP3, BR50e)
--   sp_ConfigureTicketCategory (precondition BP3)
--   sp_JoinQueue             (precondition BP11)
--   sp_CreateArtist / sp_UpdateArtist (BR50e)
-- Luu y ve du lieu mock (01_SetupMockData): he thong co DUNG MOT Admin
-- (test_admin) va Concert mock dang o trang thai OnSale.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'SP_AdminAndCatalog';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- UAI02: Admin khong duoc tu khoa chinh minh
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_AdminUpdateUserStatus @ActorUserID=@adm, @TargetUserID=@adm, @NewStatus=''Locked'';';
EXEC test.sp_RunTest @Suite,'AdminStatus_SelfLock_Fail58905','ERROR',58905,@SQL;

-- Admin tu mo khoa chinh minh (NewStatus = Active) van hop le: UAI02 chi chan khoa/vo hieu hoa
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_AdminUpdateUserStatus @ActorUserID=@adm, @TargetUserID=@adm, @NewStatus=''Active'';';
EXEC test.sp_RunTest @Suite,'AdminStatus_SelfSetActive_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- UAI01: khong duoc khoa Admin Active cuoi cung
-- Dung Admin thu hai lam Actor, roi khoa chinh Actor do sau khi
-- test_admin da bi khoa -> khong con Admin Active nao khac.
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    INSERT INTO UserAccount (Username, AccountStatus) VALUES (''tmp_admin2'', ''Active'');
    DECLARE @adm2 INT = SCOPE_IDENTITY();
    INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
    SELECT @adm2, RoleID, ''Active'' FROM Role WHERE RoleName = ''Admin'';
    -- adm2 khoa test_admin: hop le vi adm2 van con Active
    EXEC sp_AdminUpdateUserStatus @ActorUserID=@adm2, @TargetUserID=@adm, @NewStatus=''Locked'';
    -- Gio chi con adm2 la Admin Active. test_admin da bi khoa nen khong con quyen,
    -- nhung adm2 tu khoa minh se bi UAI02 chan truoc; dung Grant Admin cho cust1 roi
    -- de cust1 khoa adm2 -> luc do van con cust1 nen hop le. Vi vay kiem UAI01
    -- bang duong thu hoi Role o test ke tiep.
    SELECT 1;';
EXEC test.sp_RunTest @Suite,'AdminStatus_LockOtherAdmin_OK','SUCCESS',NULL,@SQL;

-- UAI01 qua duong thu hoi Role: test_admin tu thu hoi Role Admin cua chinh minh
-- trong khi khong con Admin Active nao khac -> phai bi chan.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_AssignRole @ActorUserID=@adm, @TargetUserID=@adm,
         @RoleName=N''Admin'', @GrantOrRevoke=''Revoke'';';
EXEC test.sp_RunTest @Suite,'AssignRole_RevokeLastAdmin_Fail58406','ERROR',58406,@SQL;

-- Thu hoi Role Admin khi VAN CON Admin khac -> hop le
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    INSERT INTO UserAccount (Username, AccountStatus) VALUES (''tmp_admin3'', ''Active'');
    DECLARE @adm3 INT = SCOPE_IDENTITY();
    INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
    SELECT @adm3, RoleID, ''Active'' FROM Role WHERE RoleName = ''Admin'';
    EXEC sp_AssignRole @ActorUserID=@adm, @TargetUserID=@adm3,
         @RoleName=N''Admin'', @GrantOrRevoke=''Revoke'';';
EXEC test.sp_RunTest @Suite,'AssignRole_RevokeNonLastAdmin_OK','SUCCESS',NULL,@SQL;

-- Admin da bi khoa thi khong con thuc thi duoc SP quan tri
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    INSERT INTO UserAccount (Username, AccountStatus) VALUES (''tmp_admin4'', ''Locked'');
    DECLARE @adm4 INT = SCOPE_IDENTITY();
    INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
    SELECT @adm4, RoleID, ''Active'' FROM Role WHERE RoleName = ''Admin'';
    -- adm4 co Role Admin Active nhung tai khoan Locked -> phai bi tu choi
    EXEC sp_AdminUpdateUserStatus @ActorUserID=@adm4, @TargetUserID=@adm, @NewStatus=''Locked'';';
EXEC test.sp_RunTest @Suite,'AdminStatus_LockedAdminActor_Fail58901','ERROR',58901,@SQL;

-- ============================================================
-- Precondition BP3: Concert mock dang OnSale
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @tcid INT = (SELECT TOP 1 TicketCategoryID FROM TicketCategory WHERE ConcertID=@cid ORDER BY TicketCategoryID);
    DECLARE @sid INT = (SELECT TOP 1 SeatID FROM Seat ORDER BY SeatID DESC);
    DECLARE @seats NVARCHAR(20) = CAST(@sid AS NVARCHAR(20));
    EXEC sp_AddEventSeats @ActorUserID=@adm, @ConcertID=@cid,
         @TicketCategoryID=@tcid, @SeatIDs=@seats;';
EXEC test.sp_RunTest @Suite,'AddEventSeats_ConcertOnSale_Fail58218','ERROR',58218,@SQL;

SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @tcid INT = NULL;
    EXEC sp_ConfigureTicketCategory @ActorUserID=@adm, @ConcertID=@cid,
         @CategoryName=N''Hang moi'', @CategoryDescription=NULL,
         @BasePrice=500000, @TicketCategoryID=@tcid OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureCategory_ConcertOnSale_Fail58206','ERROR',58206,@SQL;

-- Concert o trang thai Draft thi cau hinh duoc.
-- Luu y: KHONG duoc ha Concert mock tu OnSale ve Draft - TRG_Concert_StateTransition
-- chan dung theo BR49. Phai tao Concert Draft moi.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @src INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    INSERT INTO Concert (OrganizerUserID, ArtistID, VenueID, ConcertName, ConcertStatus,
                         StartDatetime, EndDatetime, PurchaseLimit, FairAccessEnabled,
                         WaitlistEnabled, SalesPaused)
    SELECT OrganizerUserID, ArtistID, VenueID, N''Concert Draft Test'', ''Draft'',
           DATEADD(DAY,60,SYSDATETIME()), DATEADD(DAY,60,DATEADD(HOUR,3,SYSDATETIME())),
           4, 0, 0, 0
    FROM Concert WHERE ConcertID = @src;
    DECLARE @cid INT = SCOPE_IDENTITY();
    DECLARE @tcid INT = NULL;
    EXEC sp_ConfigureTicketCategory @ActorUserID=@adm, @ConcertID=@cid,
         @CategoryName=N''Hang moi'', @CategoryDescription=NULL,
         @BasePrice=500000, @TicketCategoryID=@tcid OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM TicketCategory WHERE TicketCategoryID=@tcid AND BasePrice=500000)
        THROW 59903, ''TicketCategory khong duoc tao dung BasePrice.'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureCategory_ConcertDraft_OK','SUCCESS',NULL,@SQL;

-- BR50e: Seat da Retired khong duoc dua vao kho ve (dung Concert Draft moi)
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @src INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    INSERT INTO Concert (OrganizerUserID, ArtistID, VenueID, ConcertName, ConcertStatus,
                         StartDatetime, EndDatetime, PurchaseLimit, FairAccessEnabled,
                         WaitlistEnabled, SalesPaused)
    SELECT OrganizerUserID, ArtistID, VenueID, N''Concert Retired Seat Test'', ''Draft'',
           DATEADD(DAY,60,SYSDATETIME()), DATEADD(DAY,60,DATEADD(HOUR,3,SYSDATETIME())),
           4, 0, 0, 0
    FROM Concert WHERE ConcertID = @src;
    DECLARE @cid INT = SCOPE_IDENTITY();
    DECLARE @tcid INT = NULL;
    EXEC sp_ConfigureTicketCategory @ActorUserID=@adm, @ConcertID=@cid,
         @CategoryName=N''Hang thu'', @CategoryDescription=NULL,
         @BasePrice=500000, @TicketCategoryID=@tcid OUTPUT;
    DECLARE @sid INT = (SELECT TOP 1 s.SeatID FROM Seat s
                        JOIN Zone z ON z.ZoneID = s.ZoneID
                        WHERE z.VenueID = (SELECT VenueID FROM Concert WHERE ConcertID=@cid)
                        ORDER BY s.SeatID DESC);
    UPDATE Seat SET SeatStatus = ''Retired'' WHERE SeatID = @sid;
    DECLARE @seats NVARCHAR(20) = CAST(@sid AS NVARCHAR(20));
    EXEC sp_AddEventSeats @ActorUserID=@adm, @ConcertID=@cid,
         @TicketCategoryID=@tcid, @SeatIDs=@seats;';
EXEC test.sp_RunTest @Suite,'AddEventSeats_RetiredSeat_Fail58219','ERROR',58219,@SQL;

-- ============================================================
-- Precondition BP11: sp_JoinQueue
-- ============================================================
-- OnSale -> Cancelled la transition hop le (BR49); OnSale -> Completed thi khong,
-- nen dung Cancelled de dua Concert ve trang thai ket thuc.
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    UPDATE Concert SET FairAccessEnabled = 1 WHERE ConcertID = @cid;
    UPDATE Concert SET ConcertStatus = ''Cancelled'' WHERE ConcertID = @cid;
    DECLARE @qeid INT;
    EXEC sp_JoinQueue @ConcertID=@cid, @CustomerUserID=@uid, @NewQueueEntryID=@qeid OUTPUT;';
EXEC test.sp_RunTest @Suite,'JoinQueue_ConcertCancelled_Fail58704','ERROR',58704,@SQL;

-- ============================================================
-- sp_CreateArtist / sp_UpdateArtist
-- ============================================================
SET @SQL = N'
    DECLARE @uid INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @aid INT;
    EXEC sp_CreateArtist @ActorUserID=@uid, @ArtistName=N''Nghe si moi'',
         @ArtistDescription=NULL, @NewArtistID=@aid OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateArtist_NonAdmin_Fail59101','ERROR',59101,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @aid INT;
    EXEC sp_CreateArtist @ActorUserID=@adm, @ArtistName=N''   '',
         @ArtistDescription=NULL, @NewArtistID=@aid OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateArtist_EmptyName_Fail59102','ERROR',59102,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @aid INT;
    EXEC sp_CreateArtist @ActorUserID=@adm, @ArtistName=N''Nghe si moi'',
         @ArtistDescription=N''Mo ta'', @NewArtistID=@aid OUTPUT;
    IF NOT EXISTS (SELECT 1 FROM Artist WHERE ArtistID=@aid AND ArtistStatus=''Active'')
        THROW 59901, ''Artist khong duoc tao dung trang thai Active.'', 1;';
EXEC test.sp_RunTest @Suite,'CreateArtist_HappyPath','SUCCESS',NULL,@SQL;

-- Khong duoc Retire Artist dang gan voi Concert chua ket thuc
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert ORDER BY ConcertID);
    DECLARE @aid INT = (SELECT ArtistID FROM Concert WHERE ConcertID=@cid);
    EXEC sp_UpdateArtist @ActorUserID=@adm, @ArtistID=@aid, @ArtistStatus=''Retired'';';
EXEC test.sp_RunTest @Suite,'UpdateArtist_RetireInUse_Fail59115','ERROR',59115,@SQL;

-- Retire Artist khong gan Concert nao -> hop le
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @aid INT;
    EXEC sp_CreateArtist @ActorUserID=@adm, @ArtistName=N''Nghe si roi rac'',
         @ArtistDescription=NULL, @NewArtistID=@aid OUTPUT;
    EXEC sp_UpdateArtist @ActorUserID=@adm, @ArtistID=@aid, @ArtistStatus=''Retired'';
    IF NOT EXISTS (SELECT 1 FROM Artist WHERE ArtistID=@aid AND ArtistStatus=''Retired'')
        THROW 59902, ''Artist khong chuyen duoc sang Retired.'', 1;';
EXEC test.sp_RunTest @Suite,'UpdateArtist_RetireUnused_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    EXEC sp_UpdateArtist @ActorUserID=@adm, @ArtistID=@aid, @ArtistStatus=''Deleted'';';
EXEC test.sp_RunTest @Suite,'UpdateArtist_InvalidStatus_Fail59113','ERROR',59113,@SQL;

-- ============================================================
-- sp_UpdateRoleStatus (§12.3.2 / §24.4 / BR52)
-- Truoc khi co SP nay, gia tri Role.RoleStatus = 'Inactive' khong co bat ky duong
-- ghi nao, nen cong kiem tra kha nang phan cong trong sp_AssignRole khong bao gio
-- kich hoat duoc. Cac bai duoi day kiem ca hai chieu: cong that su dong lai duoc,
-- va viec dong cong KHONG dong thoi tuoc quyen cua nguoi dang giu vai tro.
-- ============================================================

-- Khong phai Admin -> tu choi
SET @SQL = N'
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    EXEC sp_UpdateRoleStatus @ActorUserID=@cust, @RoleName=N''Check-in Staff'', @RoleStatus=''Inactive'';';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_NonAdmin_Fail59901','ERROR',59901,@SQL;

-- Gia tri ngoai mien {Active, Inactive} -> tu choi
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Check-in Staff'', @RoleStatus=''Disabled'';';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_InvalidStatus_Fail59903','ERROR',59903,@SQL;

-- Role khong ton tai -> tu choi
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Vai tro khong co that'', @RoleStatus=''Inactive'';';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_RoleNotFound_Fail59902','ERROR',59902,@SQL;

-- Guard: Customer la Role he thong tu gan khi dang ky -> khong duoc dong
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Customer'', @RoleStatus=''Inactive'';';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_ProtectCustomer_Fail59904','ERROR',59904,@SQL;

-- Guard: Admin phai luon phan cong duoc (UAI01) -> khong duoc dong
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Admin'', @RoleStatus=''Inactive'';';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_ProtectAdmin_Fail59904','ERROR',59904,@SQL;

-- Duong di dung: dong Check-in Staff -> ghi duoc 'Inactive' VA sp_AssignRole tu choi
-- gan tiep. Bai nay moi la bai chung minh cong that su kich hoat, khong chi ghi cot.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Check-in Staff'', @RoleStatus=''Inactive'';
    IF NOT EXISTS (SELECT 1 FROM Role WHERE RoleName=N''Check-in Staff'' AND RoleStatus=''Inactive'')
        THROW 59999, ''RoleStatus khong chuyen duoc sang Inactive.'', 1;
    EXEC sp_AssignRole @ActorUserID=@adm, @TargetUserID=@cust, @RoleName=N''Check-in Staff'', @GrantOrRevoke=''Grant'';';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_InactiveBlocksAssign_Fail58403','ERROR',58403,@SQL;

-- Mo lai -> gan duoc binh thuong (chung minh cong dong/mo duoc ca hai chieu)
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust2'');
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Check-in Staff'', @RoleStatus=''Inactive'';
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Check-in Staff'', @RoleStatus=''Active'';
    EXEC sp_AssignRole @ActorUserID=@adm, @TargetUserID=@cust, @RoleName=N''Check-in Staff'', @GrantOrRevoke=''Grant'';
    IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID=ura.RoleID
                   WHERE ura.UserID=@cust AND r.RoleName=N''Check-in Staff'' AND ura.AssignmentStatus=''Active'')
        THROW 59999, ''Mo lai Role roi ma van khong gan duoc.'', 1;';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_ReactivateAllowsAssign_OK','SUCCESS',NULL,@SQL;

-- Dong Role KHONG duoc tuoc quyen cua nguoi DANG giu (§12.3.2).
-- test_org dang giu Role Organizer; sau khi dong dau vao, van phai tao duoc Concert.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM Artist ORDER BY ArtistID);
    DECLARE @vid INT = (SELECT TOP 1 VenueID FROM Venue ORDER BY VenueID);
    DECLARE @new INT;
    -- T-SQL KHONG cho phep bieu thuc lam tham so cua EXEC (chi hang hoac bien),
    -- nen moi moc thoi gian phai tinh san ra bien truoc khi goi.
    DECLARE @st DATETIME2(7) = DATEADD(day, 40, SYSDATETIME());
    DECLARE @et DATETIME2(7) = DATEADD(hour, 3, @st);
    DECLARE @ss DATETIME2(7) = DATEADD(day, 1, SYSDATETIME());
    DECLARE @se DATETIME2(7) = DATEADD(day, 39, SYSDATETIME());
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Organizer'', @RoleStatus=''Inactive'';
    EXEC sp_CreateConcert
         @OrganizerUserID=@org, @ArtistID=@aid, @VenueID=@vid,
         @ConcertName=N''Concert sau khi dong dau vao Role'',
         @StartDatetime=@st, @EndDatetime=@et,
         @SaleStartDatetime=@ss, @SaleEndDatetime=@se,
         @TemporaryHoldDuration=900, @CancellationPolicy=NULL, @RefundPolicy=NULL,
         @NewConcertID=@new OUTPUT, @ActorUserID=@org;
    IF @new IS NULL
        THROW 59999, ''Organizer dang giu Role bi mat quyen tao Concert khi Role bi dong dau vao.'', 1;';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_InactiveKeepsExistingHolders_OK','SUCCESS',NULL,@SQL;
GO
