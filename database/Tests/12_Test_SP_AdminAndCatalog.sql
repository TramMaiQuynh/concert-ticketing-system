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
    INSERT INTO Concert (OrganizerUserID, VenueID, ConcertName, ConcertStatus,
                         StartDatetime, EndDatetime, PurchaseLimit, FairAccessEnabled,
                         WaitlistEnabled, SalesPaused)
    SELECT OrganizerUserID, VenueID, N''Concert Draft Test'', ''Draft'',
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
    INSERT INTO Concert (OrganizerUserID, VenueID, ConcertName, ConcertStatus,
                         StartDatetime, EndDatetime, PurchaseLimit, FairAccessEnabled,
                         WaitlistEnabled, SalesPaused)
    SELECT OrganizerUserID, VenueID, N''Concert Retired Seat Test'', ''Draft'',
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
    DECLARE @aid INT = (SELECT TOP 1 ArtistID FROM ConcertArtist WHERE ConcertID=@cid);
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
    -- Cung ly do voi cac moc thoi gian o tren: T-SQL KHONG cho truyen bieu thuc lam
    -- doi so EXEC (chi hang hoac bien), nen chuoi JSON cung phai tinh san ra bien.
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@aid AS NVARCHAR(12)) + N'']'';
    EXEC sp_UpdateRoleStatus @ActorUserID=@adm, @RoleName=N''Organizer'', @RoleStatus=''Inactive'';
    EXEC sp_CreateConcert
         @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@vid,
         @ConcertName=N''Concert sau khi dong dau vao Role'',
         @StartDatetime=@st, @EndDatetime=@et,
         @SaleStartDatetime=@ss, @SaleEndDatetime=@se,
         @TemporaryHoldDuration=900, @CancellationPolicy=NULL, @RefundPolicy=NULL,
         @NewConcertID=@new OUTPUT, @ActorUserID=@org;
    IF @new IS NULL
        THROW 59999, ''Organizer dang giu Role bi mat quyen tao Concert khi Role bi dong dau vao.'', 1;';
EXEC test.sp_RunTest @Suite,'UpdateRoleStatus_InactiveKeepsExistingHolders_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_ConfigureVenueMap (FR11a)
--
-- Truoc dot nay day la thu tuc GHI DU LIEU duy nhat khong co bat ky bai kiem nao
-- cham toi - khong o test SQL, khong o test tich hop backend. Moi bai duoi day TU TAO
-- Venue rieng bang sp_CreateVenue, nen khong bai nao phu thuoc trang thai bai khac
-- de lai va thu tu chay khong anh huong ket qua.
-- ============================================================

-- 59801: chi Admin duoc cau hinh so do
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM auth'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@org, @VenueID=@v, @MapWidth=100, @MapHeight=100;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_NonAdmin_Fail59801','ERROR',59801,@SQL;

-- 59802: Venue khong ton tai
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=-1, @MapWidth=100, @MapHeight=100;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_VenueNotFound_Fail59802','ERROR',59802,@SQL;

-- 59803: kich thuoc mat phang phai > 0
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM dim'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=0, @MapHeight=100;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_ZeroWidth_Fail59803','ERROR',59803,@SQL;

-- 59805: san khau phai co du bon gia tri
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM stage partial'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100, @StageX=10;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_PartialStage_Fail59805','ERROR',59805,@SQL;

-- 59806: chua co mat phang thi khong dat duoc san khau
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM no plane'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @StageX=10, @StageY=10, @StageWidth=10, @StageHeight=10;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_StageWithoutPlane_Fail59806','ERROR',59806,@SQL;

-- 59807: san khau phai nam tron trong mat phang
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM stage out'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100,
         @StageX=90, @StageY=10, @StageWidth=20, @StageHeight=10;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_StageOutsidePlane_Fail59807','ERROR',59807,@SQL;

-- 59804: thu nho mat phang xuong duoi vung cac Zone dang chiem
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM shrink'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=200, @MapHeight=200;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''Khu 1'',
         @ZoneX=150, @ZoneY=150, @ZoneWidth=40, @ZoneHeight=40, @NewZoneID=@z OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_ShrinkBelowZones_Fail59804','ERROR',59804,@SQL;

-- Happy path: ghi dung ca sau gia tri
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM happy'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=800, @MapHeight=600,
         @StageX=300, @StageY=20, @StageWidth=200, @StageHeight=80;
    IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID=@v
                     AND MapWidth=800 AND MapHeight=600
                     AND StageX=300 AND StageY=20 AND StageWidth=200 AND StageHeight=80)
        THROW 59999, ''Sau khi cau hinh, sau gia tri so do phai duoc ghi dung'', 1;
    IF NOT EXISTS (SELECT 1 FROM AuditRecord
                   WHERE EntityType=''Venue'' AND EntityID=CAST(@v AS VARCHAR(64))
                     AND EventType=''VENUE_MAP_CONFIGURED'')
        THROW 59999, ''Phai ghi AuditRecord VENUE_MAP_CONFIGURED'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_HappyPath_OK','SUCCESS',NULL,@SQL;

-- Cap nhat mot phan: chi doi mat phang thi san khau phai duoc GIU (COALESCE)
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM partial'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=800, @MapHeight=600,
         @StageX=300, @StageY=20, @StageWidth=200, @StageHeight=80;
    -- Chi noi rong mat phang, khong nhac gi den san khau
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=1000, @MapHeight=700;
    IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID=@v
                     AND MapWidth=1000 AND MapHeight=700
                     AND StageX=300 AND StageY=20 AND StageWidth=200 AND StageHeight=80)
        THROW 59999, ''Cap nhat mot phan phai giu nguyen san khau da dat truoc do'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_PartialUpdateKeepsStage_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_CreateZone / sp_UpdateZone / sp_CreateSeat / sp_UpdateSeat - kiem tra hinh hoc
--
-- Truoc dot nay, 13 ma loi rieng biet (59811-59819, 59821-59824) trai tren bon
-- thu tuc nay KHONG co bai kiem nao cham toi: moi lan goi trong toan bo bo test
-- deu bo trong tham so hinh hoc. Danh muc duoi day phu het ca 13 ma, uu tien kep
-- cho 59814/59815 (dung duong vua sua WITH (UPDLOCK)) va 59824 (co nhanh loai tru
-- chinh no o UpdateSeat ma CreateSeat khong co).
-- ============================================================

-- 59831: Reserved seating hien chi ho tro ZoneType=Seated.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG InvalidType'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneType=''Bogus'', @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_UnsupportedType_Fail59831','ERROR',59831,@SQL;

-- 59812: hop bao vi tri phai du X,Y,Width,Height hoac khong co gi
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG Incomplete'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=10, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_IncompletePosition_Fail59812','ERROR',59812,@SQL;

-- 59813: kich thuoc khu phai lon hon 0
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG ZeroSize'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=0, @ZoneY=0, @ZoneWidth=0, @ZoneHeight=10, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_ZeroSize_Fail59813','ERROR',59813,@SQL;

-- 59814 (qua sp_CreateZone): chua cau hinh so do dia diem
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG NoMap'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=10, @ZoneY=10, @ZoneWidth=10, @ZoneHeight=10, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_MapNotConfigured_Fail59814','ERROR',59814,@SQL;

-- 59815 (qua sp_CreateZone): khu nam ngoai mat phang
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG Outside'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=90, @ZoneY=90, @ZoneWidth=50, @ZoneHeight=50, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_OutsideMap_Fail59815','ERROR',59815,@SQL;

-- 59816: goc xoay ngoai khoang -360..360
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG Rotation'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneRotation=400, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_RotationOutOfRange_Fail59816','ERROR',59816,@SQL;

-- GeneralAdmission khong duoc mo phong bang Zone khong co Seat.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG GACapMissing'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneType=''GeneralAdmission'', @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_GeneralAdmissionUnsupported_Fail59831','ERROR',59831,@SQL;

-- 59818: chi khu ve dung moi duoc khai bao suc chua
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG SeatedWithCap'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneType=''Seated'', @ZoneCapacity=100, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_SeatedWithCapacity_Fail59818','ERROR',59818,@SQL;

-- 59814 (qua sp_UpdateZone - dung duong vua sua WITH (UPDLOCK))
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZGU NoMap'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_UpdateZone @ActorUserID=@adm, @ZoneID=@z, @ZoneX=10, @ZoneY=10, @ZoneWidth=10, @ZoneHeight=10;';
EXEC test.sp_RunTest @Suite,'ZoneUpdate_MapNotConfigured_Fail59814','ERROR',59814,@SQL;

-- 59815 (qua sp_UpdateZone - di chuyen mot khu DANG hop le ra ngoai bien)
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZGU Outside'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=10, @ZoneY=10, @ZoneWidth=10, @ZoneHeight=10, @NewZoneID=@z OUTPUT;
    EXEC sp_UpdateZone @ActorUserID=@adm, @ZoneID=@z, @ZoneX=90, @ZoneY=90, @ZoneWidth=50, @ZoneHeight=50;';
EXEC test.sp_RunTest @Suite,'ZoneUpdate_OutsideMap_Fail59815','ERROR',59815,@SQL;

-- 59815 doi chung duong: vi tri moi HOP LE phai duoc chap nhan va ghi dung
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZGU Reposition'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=5, @ZoneY=5, @ZoneWidth=10, @ZoneHeight=10, @NewZoneID=@z OUTPUT;
    EXEC sp_UpdateZone @ActorUserID=@adm, @ZoneID=@z, @ZoneX=20, @ZoneY=20, @ZoneWidth=15, @ZoneHeight=15;
    IF NOT EXISTS (SELECT 1 FROM Zone WHERE ZoneID=@z AND ZoneX=20 AND ZoneY=20 AND ZoneWidth=15 AND ZoneHeight=15)
        THROW 59999, ''Vi tri moi hop le phai duoc ghi dung'', 1;';
EXEC test.sp_RunTest @Suite,'ZoneUpdate_ValidReposition_OK','SUCCESS',NULL,@SQL;

-- Chuyen sang GeneralAdmission bi chan truoc khi lam thay doi mo hinh kho ve.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZGU ToGA'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneType=''Seated'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'', @SeatRowLabel=N''A'', @SeatColumnNumber=1, @NewSeatID=@s OUTPUT;
    EXEC sp_UpdateZone @ActorUserID=@adm, @ZoneID=@z, @ZoneType=''GeneralAdmission'', @ZoneCapacity=100;';
EXEC test.sp_RunTest @Suite,'ZoneUpdate_GeneralAdmissionUnsupported_Fail59831','ERROR',59831,@SQL;

-- 59821: hang va so thu tu trong hang phai di cung nhau
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG RowColMismatch'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @NewSeatID=@s OUTPUT;';
EXEC test.sp_RunTest @Suite,'SeatCreate_RowColumnMismatch_Fail59821','ERROR',59821,@SQL;

-- 59822: so thu tu trong hang phai lon hon 0
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG ColZero'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=0, @NewSeatID=@s OUTPUT;';
EXEC test.sp_RunTest @Suite,'SeatCreate_ColumnNotPositive_Fail59822','ERROR',59822,@SQL;

-- GeneralAdmission khong duoc tao trong phien ban chi ban theo Seat.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG SeatInGA'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''ZGA'', @ZoneName=N''x'',
         @ZoneType=''GeneralAdmission'', @ZoneCapacity=100, @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s OUTPUT;';
EXEC test.sp_RunTest @Suite,'SeatCreate_GeneralAdmissionUnsupported_Fail59831','ERROR',59831,@SQL;

-- SeatCode la duy nhat trong Zone, khong phai trong ca Venue.
-- Cung A1 o hai Zone cua mot Venue phai tao duoc.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z1 INT, @z2 INT, @s1 INT, @s2 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG CodePerZone'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z1 OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z2'', @ZoneName=N''x'', @NewZoneID=@z2 OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z1, @SeatCode=''A1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s1 OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z2, @SeatCode=''A1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s2 OUTPUT;
    IF @s1 IS NULL OR @s2 IS NULL THROW 59999, ''A1 phai tao duoc o hai Zone khac nhau.'', 1;';
EXEC test.sp_RunTest @Suite,'SeatCreate_SameCodeInDifferentZones_OK','SUCCESS',NULL,@SQL;

-- Nhưng trong cùng Zone thì phải trả lỗi nghiệp vụ rõ ràng, kể cả khi vị trí lưới khác.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s1 INT, @s2 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG DuplicateCode'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''A1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s1 OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''A1'', @SeatLabel=N''x'',
         @SeatRowLabel=''B'', @SeatColumnNumber=1, @NewSeatID=@s2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'SeatCreate_DuplicateCodeInSameZone_Fail58124','ERROR',58124,@SQL;

-- 59824 (qua sp_CreateSeat): trung o luoi voi mot ghe dang hoat dong khac
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s1 INT, @s2 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG GridCollide'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s1 OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S2'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'SeatCreate_GridSlotCollision_Fail59824','ERROR',59824,@SQL;

-- Doi chung duong: vi tri luoi hop le phai duoc chap nhan
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG ValidGrid'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s OUTPUT;
    IF @s IS NULL THROW 59999, ''Ghe hop le phai duoc tao'', 1;';
EXEC test.sp_RunTest @Suite,'SeatCreate_ValidGridPosition_OK','SUCCESS',NULL,@SQL;

-- 59824 (qua sp_UpdateSeat) doi chung AM: chuyen mot ghe VE DUNG cho hien tai cua
-- no khong duoc tu bao trung voi chinh no (kiem tra nhanh loai tru SeatID<>@SeatID).
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s1 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SGU SelfSlot'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s1 OUTPUT;
    EXEC sp_UpdateSeat @ActorUserID=@adm, @SeatID=@s1, @SeatRowLabel=''A'', @SeatColumnNumber=1;';
EXEC test.sp_RunTest @Suite,'SeatUpdate_MoveToOwnCurrentSlot_OK','SUCCESS',NULL,@SQL;

-- 59824 (qua sp_UpdateSeat) doi chung DUONG: chuyen sang o luoi cua MOT GHE KHAC
-- van phai bi chan (nhanh loai tru chinh no khong duoc lam mat kha nang phat hien
-- trung voi ghe khac).
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s1 INT, @s2 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SGU CollideOther'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s1 OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''S2'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=2, @NewSeatID=@s2 OUTPUT;
    EXEC sp_UpdateSeat @ActorUserID=@adm, @SeatID=@s2, @SeatRowLabel=''A'', @SeatColumnNumber=1;';
EXEC test.sp_RunTest @Suite,'SeatUpdate_MoveToOccupiedSlot_Fail59824','ERROR',59824,@SQL;

-- Map la mot cap width/height; khong cho phep tao cau hinh nua vo.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM HalfMap'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_PartialMap_Fail59803','ERROR',59803,@SQL;

-- Xoa san khau va xoa map la hai thao tac ro rang, khong dung NULL sentinel.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM Clear'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100,
         @StageX=40, @StageY=10, @StageWidth=20, @StageHeight=10;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @ClearStage=1;
    IF EXISTS (SELECT 1 FROM Venue WHERE VenueID=@v AND StageX IS NOT NULL)
        THROW 59999, ''ClearStage phai xoa tron ven san khau'', 1;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @ClearMap=1;
    IF EXISTS (SELECT 1 FROM Venue WHERE VenueID=@v
                 AND (MapWidth IS NOT NULL OR MapHeight IS NOT NULL
                      OR StageX IS NOT NULL OR StageY IS NOT NULL OR StageWidth IS NOT NULL OR StageHeight IS NOT NULL))
        THROW 59999, ''ClearMap phai xoa ca map va san khau'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_ClearStageAndMap_OK','SUCCESS',NULL,@SQL;

-- Khu xoay 45 do co the vuot bien du hop bao truoc xoay van nam trong map.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG RotatedOutside'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=80, @ZoneY=30, @ZoneWidth=20, @ZoneHeight=20, @ZoneRotation=45, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_RotatedOutsideMap_Fail59815','ERROR',59815,@SQL;

-- Stage khong duoc dat de len Zone, va Zone cung khong duoc tao de len Stage.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''VM StageOverlap'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=100, @MapHeight=100;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=10, @ZoneY=10, @ZoneWidth=20, @ZoneHeight=20, @NewZoneID=@z OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v,
         @StageX=20, @StageY=20, @StageWidth=20, @StageHeight=20;';
EXEC test.sp_RunTest @Suite,'ConfigureVenueMap_StageOverlapsZone_Fail59820','ERROR',59820,@SQL;

-- Cac khu cung tang la cac vung ban ve rieng, khong duoc chong len nhau.
-- Tang khac van co the dung cung hinh chieu, vi nguoi mua xem tung tang mot.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z1 INT, @z2 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG SameLevelOverlap'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=200, @MapHeight=200;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @ZoneLevel=1,
         @ZoneX=20, @ZoneY=20, @ZoneWidth=60, @ZoneHeight=50, @NewZoneID=@z1 OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z2'', @ZoneName=N''x'', @ZoneLevel=1,
         @ZoneX=60, @ZoneY=40, @ZoneWidth=60, @ZoneHeight=50, @NewZoneID=@z2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_SameLevelOverlap_Fail59832','ERROR',59832,@SQL;

SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z1 INT, @z2 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG DifferentLevels'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=200, @MapHeight=200;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''L1'', @ZoneName=N''x'', @ZoneLevel=1,
         @ZoneX=20, @ZoneY=20, @ZoneWidth=60, @ZoneHeight=50, @NewZoneID=@z1 OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''L2'', @ZoneName=N''x'', @ZoneLevel=2,
         @ZoneX=20, @ZoneY=20, @ZoneWidth=60, @ZoneHeight=50, @NewZoneID=@z2 OUTPUT;
    IF (SELECT COUNT(*) FROM Zone WHERE ZoneID IN (@z1, @z2)) <> 2
        THROW 59999, ''Hai khu o hai tang phai duoc phep dung cung hinh chieu'', 1;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_DifferentLevelsMayOverlap_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z1 INT, @z2 INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG UpdateOverlap'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_ConfigureVenueMap @ActorUserID=@adm, @VenueID=@v, @MapWidth=200, @MapHeight=200;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'',
         @ZoneX=20, @ZoneY=20, @ZoneWidth=60, @ZoneHeight=50, @NewZoneID=@z1 OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z2'', @ZoneName=N''x'',
         @ZoneX=120, @ZoneY=20, @ZoneWidth=40, @ZoneHeight=50, @NewZoneID=@z2 OUTPUT;
    EXEC sp_UpdateZone @ActorUserID=@adm, @ZoneID=@z2, @ZoneX=50, @ZoneY=20, @ZoneWidth=40, @ZoneHeight=50;';
EXEC test.sp_RunTest @Suite,'ZoneUpdate_SameLevelOverlap_Fail59832','ERROR',59832,@SQL;

SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''ZG InvalidLevel'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @ZoneLevel=0, @NewZoneID=@z OUTPUT;';
EXEC test.sp_RunTest @Suite,'ZoneCreate_InvalidLevel_Fail59833','ERROR',59833,@SQL;

-- Tao luoi ghe la mot giao dich.
--
-- LUU Y VE PHAM VI: sp_RunTest boc MOI test trong BEGIN TRAN/ROLLBACK, con cac SP
-- nghiep vu deu dung `IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION` trong CATCH - lenh do
-- huy CA transaction ngoai chu khong rieng phan viec cua SP. Vi vay trong khung nay
-- KHONG test nao co the bat loi cua mot SP roi chay tiep de kiem tra trang thai con
-- lai: @@TRANCOUNT tut ve 0 va SQL Server bao loi 266 ngay khi EXEC tra ve.
--
-- Hai test duoi day vi the chi khang dinh nhung gi kiem chung duoc o day. Khang dinh
-- "loi khong de lai ghe ghi mot phan" nam o test tich hop
-- AdminRepositoryTests.CreateSeatsBatch_* - noi loi goi KHONG nam trong transaction
-- bao ngoai, tuc dung moi truong ma tinh chat nay co y nghia.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG Batch'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeatsBatch @ActorUserID=@adm, @ZoneID=@z,
         @SeatsJson=N''[{"seatCode":"A1","seatLabel":"A1","seatRowLabel":"A","seatColumnNumber":1},{"seatCode":"A2","seatLabel":"A2","seatRowLabel":"A","seatColumnNumber":2}]'';
    IF (SELECT COUNT(*) FROM Seat WHERE ZoneID=@z) <> 2
        THROW 59999, ''Batch phai tao du hai ghe'', 1;';
EXEC test.sp_RunTest @Suite,'CreateSeatsBatch_CreatesWholeGrid_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SG Batch Dup'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeatsBatch @ActorUserID=@adm, @ZoneID=@z,
         @SeatsJson=N''[{"seatCode":"A1","seatLabel":"A1","seatRowLabel":"A","seatColumnNumber":1}]'';
    -- Lo hang thu hai chua mot ma ghe DA ton tai trong khu: phai bi tu choi nguyen lo.
    EXEC sp_CreateSeatsBatch @ActorUserID=@adm, @ZoneID=@z,
         @SeatsJson=N''[{"seatCode":"B1","seatLabel":"B1","seatRowLabel":"B","seatColumnNumber":1},{"seatCode":"A1","seatLabel":"A1","seatRowLabel":"B","seatColumnNumber":2}]'';';
EXEC test.sp_RunTest @Suite,'CreateSeatsBatch_DuplicateCode_Fail58124','ERROR',58124,@SQL;

-- PATCH Seat co the doi rieng cot va van giu hang hien tai.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @v INT, @z INT, @s INT;
    EXEC sp_CreateVenue @ActorUserID=@adm, @VenueName=N''SGU PartialGrid'', @Address=N''x'', @NewVenueID=@v OUTPUT;
    EXEC sp_CreateZone @ActorUserID=@adm, @VenueID=@v, @ZoneCode=''Z1'', @ZoneName=N''x'', @NewZoneID=@z OUTPUT;
    EXEC sp_CreateSeat @ActorUserID=@adm, @ZoneID=@z, @SeatCode=''A1'', @SeatLabel=N''x'',
         @SeatRowLabel=''A'', @SeatColumnNumber=1, @NewSeatID=@s OUTPUT;
    EXEC sp_UpdateSeat @ActorUserID=@adm, @SeatID=@s, @SeatColumnNumber=2;
    IF NOT EXISTS (SELECT 1 FROM Seat WHERE SeatID=@s AND SeatRowLabel=''A'' AND SeatColumnNumber=2)
        THROW 59999, ''PATCH cot phai giu hang hien tai'', 1;';
EXEC test.sp_RunTest @Suite,'UpdateSeat_PartialGridPosition_OK','SUCCESS',NULL,@SQL;
GO
