-- ============================================================
-- 19_Test_StagePass_ConcertMapSP.sql
-- Kiem chung 3 SP tang ConcertMap (StagePass D.5): sp_CreateConcertMap,
-- sp_CreateConcertMapRevision, sp_LockConcertMapRevision.
-- Cung khuon cac file 16/18: goi qua SP, moi test tu dung du lieu cua
-- chinh no (sp_RunTest luon ROLLBACK).
-- ============================================================
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StagePass_ConcertMapSP';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- sp_CreateConcertMap
-- ============================================================
SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CM OK'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    IF @cm IS NULL THROW 59999, ''ConcertMapID phai duoc gan'', 1;';
EXEC test.sp_RunTest @Suite,'CreateConcertMap_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CM NotOwner'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@cust, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMap_NotOwnerNotAdmin_Fail60202','ERROR',60202,@SQL;

SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CM Dup'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm1 INT, @cm2 INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm1 OUTPUT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMap_Duplicate_Fail60203','ERROR',60203,@SQL;

SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=-1, @NewConcertMapID=@cm OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMap_ConcertNotExist_Fail60201','ERROR',60201,@SQL;

-- ============================================================
-- sp_CreateConcertMapRevision
-- ============================================================
-- Duong hanh phuc + kiem tra sao chep sau DUNG so luong, EventSeatID=NULL.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @s2  INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID <> @s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT, @ts2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG CMR OK'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s2, @SeatKey=N''S2'', @RowLabel=N''A'', @SeatNumber=2, @TemplateSeatID=@ts2 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CMR OK Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    IF @cmr IS NULL THROW 59999, ''ConcertMapRevisionID phai duoc gan'', 1;

    IF (SELECT COUNT(*) FROM ConcertMapRevisionFloor WHERE ConcertMapRevisionID=@cmr) <> 1
        THROW 59999, ''Phai sao chep dung 1 Floor'', 1;
    DECLARE @cmrf INT = (SELECT TOP 1 ConcertMapRevisionFloorID FROM ConcertMapRevisionFloor WHERE ConcertMapRevisionID=@cmr);
    IF (SELECT COUNT(*) FROM ConcertMapRevisionSection WHERE ConcertMapRevisionFloorID=@cmrf) <> 1
        THROW 59999, ''Phai sao chep dung 1 Section'', 1;
    DECLARE @cmrs INT = (SELECT TOP 1 ConcertMapRevisionSectionID FROM ConcertMapRevisionSection WHERE ConcertMapRevisionFloorID=@cmrf);
    IF (SELECT COUNT(*) FROM ConcertMapRevisionSeat WHERE ConcertMapRevisionSectionID=@cmrs) <> 2
        THROW 59999, ''Phai sao chep dung 2 Seat'', 1;
    IF EXISTS (SELECT 1 FROM ConcertMapRevisionSeat WHERE ConcertMapRevisionSectionID=@cmrs AND EventSeatID IS NOT NULL)
        THROW 59999, ''EventSeatID phai la NULL ngay sau khi snapshot (chua gan inventory)'', 1;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @vt INT, @vtv INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG CMR NotPublished'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CMR NotPublished Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_SourceNotPublished_Fail60215','ERROR',60215,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven1 INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);

    DECLARE @ven2 INT;
    EXEC dbo.sp_CreateVenue @ActorUserID=@adm, @VenueName=N''REG CMR VenueMismatch Venue2'', @Address=N''123 Test St'', @NewVenueID=@ven2 OUTPUT;
    DECLARE @zone2 INT;
    EXEC dbo.sp_CreateZone @ActorUserID=@adm, @VenueID=@ven2, @ZoneCode=N''Z1'', @ZoneName=N''Zone 1'', @NewZoneID=@zone2 OUTPUT;
    DECLARE @seat2 INT;
    EXEC dbo.sp_CreateSeat @ActorUserID=@adm, @ZoneID=@zone2, @SeatCode=N''A1'', @SeatLabel=N''A1'', @SeatRowLabel=N''A'', @SeatColumnNumber=1, @NewSeatID=@seat2 OUTPUT;

    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven2, @TemplateName=N''REG CMR VenueMismatch Template'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zone2, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@seat2, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven1,
         @ConcertName=N''REG CMR VenueMismatch Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_VenueMismatch_Fail60216','ERROR',60216,@SQL;

SET @SQL = N'
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @vt INT, @vtv INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG CMR NotOwner'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CMR NotOwner Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@cust, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_NotOwnerNotAdmin_Fail60212','ERROR',60212,@SQL;

SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @vtv INT = (SELECT TOP 1 VenueTemplateVersionID FROM VenueTemplateVersion);
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=-1, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_MapNotExist_Fail60211','ERROR',60211,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG CMR DraftOpen'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CMR DraftOpen Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr1 INT, @cmr2 INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr1 OUTPUT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_DraftAlreadyOpen_Fail60217','ERROR',60217,@SQL;

-- Concert chua duoc gan Venue (chi dat toi duoc bang thao tac tho vi
-- sp_CreateConcert luon bat buoc @VenueID â€” day la truong hop bien khong
-- the xay ra qua luong nghiep vu binh thuong, nhung SP van phai tu ve).
SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG CMR NoVenue Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    UPDATE Concert SET VenueID = NULL WHERE ConcertID = @cid;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @vtv INT = (SELECT TOP 1 VenueTemplateVersionID FROM VenueTemplateVersion);
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_ConcertNoVenue_Fail60213','ERROR',60213,@SQL;

-- ============================================================
-- sp_LockConcertMapRevision
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Lock OK'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Lock OK Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;
    IF (SELECT RevisionStatus FROM ConcertMapRevision WHERE ConcertMapRevisionID=@cmr) <> ''Locked''
        THROW 59999, ''RevisionStatus phai la Locked'', 1;
    IF (SELECT LockedTimestamp FROM ConcertMapRevision WHERE ConcertMapRevisionID=@cmr) IS NULL
        THROW 59999, ''LockedTimestamp khong duoc NULL sau khi Lock'', 1;';
EXEC test.sp_RunTest @Suite,'LockConcertMapRevision_OK','SUCCESS',NULL,@SQL;

-- Gia lap revision rong bang cach xoa het ConcertMapRevisionSeat sau khi
-- snapshot (kich ban khong the xay ra qua luong SP binh thuong vi
-- sp_PublishVenueTemplateVersion da tu choi publish version rong o
-- 60024 â€” day la kiem tra phong thu SP, dung ky thuat thao tac tho da
-- dung xuyen suot bo test nay cho cac bat bien khong dat toi duoc qua SP).
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Lock Empty'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Lock Empty Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    DELETE sv FROM ConcertMapRevisionSeat sv
    JOIN ConcertMapRevisionSection s2 ON s2.ConcertMapRevisionSectionID = sv.ConcertMapRevisionSectionID
    JOIN ConcertMapRevisionFloor f2 ON f2.ConcertMapRevisionFloorID = s2.ConcertMapRevisionFloorID
    WHERE f2.ConcertMapRevisionID = @cmr;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;';
EXEC test.sp_RunTest @Suite,'LockConcertMapRevision_Empty_Fail60234','ERROR',60234,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Lock Twice'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Lock Twice Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;';
EXEC test.sp_RunTest @Suite,'LockConcertMapRevision_NotDraft_Fail60233','ERROR',60233,@SQL;

-- LUU Y: test nay tung mong doi tao va Lock duoc mot revision THU HAI sau khi
-- revision dau da Locked, chuyen revision dau sang trang thai 'Replaced'. Trang
-- thai 'Replaced' da bi GO KHOI schema (xem CHK_CMR_Status trong
-- ConcertMapRevision.sql: chi con 'Draft'/'Locked') va sp_CreateConcertMapRevision
-- gio tu choi thang (60219) viec tao them revision moi khi Map da co mot Locked —
-- "revision Locked la tai lieu cong khai bat bien, khong co duong thay the" (xem
-- comment sp_LockConcertMapRevision.sql). Cap nhat test de kiem chung DUNG hanh vi
-- hien tai: sp_CreateConcertMapRevision phai TU CHOI ngay tu buoc tao cmr2.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Lock Replace'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Lock Replace Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr1 INT, @cmr2 INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr1 OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr1;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcertMapRevision_CannotReplaceLocked_Fail60219','ERROR',60219,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Lock NotOwner'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Lock NotOwner Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@cust, @ConcertMapRevisionID=@cmr;';
EXEC test.sp_RunTest @Suite,'LockConcertMapRevision_NotOwnerNotAdmin_Fail60232','ERROR',60232,@SQL;

-- ============================================================
-- sp_CancelConcertMapRevisionDraft
-- ============================================================
-- Duong hanh phuc + pham vi xoa: revision cua MOT map khac KHONG bi dung toi.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Cancel OK'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());

    -- Concert A: se bi huy Draft.
    DECLARE @cidA INT; DECLARE @cmA INT; DECLARE @cmrA INT;
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Cancel A'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cidA OUTPUT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cidA, @NewConcertMapID=@cmA OUTPUT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cmA, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmrA OUTPUT;

    -- Concert B: phai con nguyen ven sau khi huy Draft cua A.
    DECLARE @cidB INT; DECLARE @cmB INT; DECLARE @cmrB INT;
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Cancel B'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cidB OUTPUT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cidB, @NewConcertMapID=@cmB OUTPUT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cmB, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmrB OUTPUT;

    EXEC dbo.sp_CancelConcertMapRevisionDraft @ActorUserID=@org, @ConcertMapRevisionID=@cmrA;

    -- (1) Revision A va toan bo cay con da bi xoa.
    IF EXISTS (SELECT 1 FROM ConcertMapRevision WHERE ConcertMapRevisionID=@cmrA)
        THROW 59999, ''Revision A phai bi xoa'', 1;
    IF EXISTS (SELECT 1 FROM ConcertMapRevisionFloor WHERE ConcertMapRevisionID=@cmrA)
        THROW 59999, ''Floor cua A phai bi xoa'', 1;
    IF EXISTS (SELECT 1 FROM ConcertMapRevisionSeat cs
               JOIN ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID=cs.ConcertMapRevisionSectionID
               JOIN ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID=sec.ConcertMapRevisionFloorID
               WHERE f.ConcertMapRevisionID=@cmrA)
        THROW 59999, ''Seat cua A phai bi xoa'', 1;

    -- (2) Revision B KHONG bi dung toi (xoa dung pham vi).
    IF NOT EXISTS (SELECT 1 FROM ConcertMapRevision WHERE ConcertMapRevisionID=@cmrB AND RevisionStatus=''Draft'')
        THROW 59999, ''Revision cua Concert khac khong duoc bi anh huong'', 1;

    -- (3) Vet kiem toan con lai du dong nghiep vu da bi xoa.
    IF NOT EXISTS (SELECT 1 FROM AuditRecord
                   WHERE EventType=''CONCERT_MAP_REVISION_DRAFT_CANCELLED'' AND EntityID=CAST(@cmrA AS VARCHAR(64)))
        THROW 59999, ''Phai co AuditRecord CONCERT_MAP_REVISION_DRAFT_CANCELLED'', 1;';
EXEC test.sp_RunTest @Suite,'CancelConcertMapRevisionDraft_OK_ScopedAndAudited','SUCCESS',NULL,@SQL;

-- DAY LA DONG LUC CHINH CUA SP: truoc khi co no, mot Draft snapshot nham lam 60217
-- chan vinh vien (khong huy duoc Draft, khong tao Draft moi duoc, khong thay duoc
-- revision Locked — 60236/60219/UIX_CMR_OneLockedPerMap). Sau khi huy duoc thi
-- phai mo lai duoc Draft moi, snapshot day du, va van la Draft.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Cancel Redo'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Cancel Redo Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;

    DECLARE @cmrOld INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmrOld OUTPUT;

    -- Snapshot nham -> huy.
    EXEC dbo.sp_CancelConcertMapRevisionDraft @ActorUserID=@org, @ConcertMapRevisionID=@cmrOld;

    -- Phai TAO DUOC Draft moi. Truoc ban sua, buoc nay nem 60217.
    DECLARE @cmrNew INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmrNew OUTPUT;
    IF @cmrNew IS NULL THROW 59999, ''Phai tao duoc Draft moi sau khi huy Draft cu'', 1;
    IF @cmrNew = @cmrOld THROW 59999, ''Draft moi phai la revision khac'', 1;
    IF NOT EXISTS (SELECT 1 FROM ConcertMapRevision WHERE ConcertMapRevisionID=@cmrNew AND RevisionStatus=''Draft'')
        THROW 59999, ''Draft moi phai dang o trang thai Draft'', 1;
    IF NOT EXISTS (SELECT 1 FROM ConcertMapRevisionSeat cs
                   JOIN ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID=cs.ConcertMapRevisionSectionID
                   JOIN ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID=sec.ConcertMapRevisionFloorID
                   WHERE f.ConcertMapRevisionID=@cmrNew AND cs.EventSeatID IS NULL)
        THROW 59999, ''Draft moi phai duoc snapshot day du cay va EventSeatID=NULL'', 1;';
EXEC test.sp_RunTest @Suite,'CancelConcertMapRevisionDraft_ThenCreateNewDraft_OK','SUCCESS',NULL,@SQL;

-- Revision da Locked la ban do dang ban cua Concert — khong huy duoc (60237).
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Cancel Locked'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Cancel Locked Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;
    EXEC dbo.sp_CancelConcertMapRevisionDraft @ActorUserID=@org, @ConcertMapRevisionID=@cmr;';
EXEC test.sp_RunTest @Suite,'CancelConcertMapRevisionDraft_Locked_Fail60237','ERROR',60237,@SQL;

-- Khach hang (khong phai Organizer so huu, khong phai Admin) khong huy duoc.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Cancel NotOwner'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Cancel NotOwner Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_CancelConcertMapRevisionDraft @ActorUserID=@cust, @ConcertMapRevisionID=@cmr;';
EXEC test.sp_RunTest @Suite,'CancelConcertMapRevisionDraft_NotOwnerNotAdmin_Fail60232','ERROR',60232,@SQL;

-- Revision khong ton tai (60231).
SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    EXEC dbo.sp_CancelConcertMapRevisionDraft @ActorUserID=@org, @ConcertMapRevisionID=-1;';
EXEC test.sp_RunTest @Suite,'CancelConcertMapRevisionDraft_NotExist_Fail60231','ERROR',60231,@SQL;
