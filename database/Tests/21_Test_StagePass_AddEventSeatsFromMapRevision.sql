-- ============================================================
-- 21_Test_StagePass_AddEventSeatsFromMapRevision.sql
-- Kiem chung sp_AddEventSeatsFromMapRevision — cau noi con thieu giua
-- ConcertMapRevisionSeat va EventSeat (xem comment trong chinh SP va trong
-- ConcertMapRevisionSeat.sql). Cung khuon file 19/20: goi qua SP, moi test tu
-- dung du lieu cua chinh no (sp_RunTest luon ROLLBACK).
-- ============================================================
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StagePass_AddEventSeatsFromMapRevision';
DECLARE @SQL NVARCHAR(MAX);

-- Khuon dung chung: template 1 tang, 1 khu, 2 ghe -> publish -> concert ->
-- concertmap -> revision -> lock -> ticket category. Duong hanh phuc kiem tra
-- CA HAI: EventSeat duoc tao dung SalePrice = BasePrice, VA ConcertMapRevisionSeat
-- duoc ghi nguoc EventSeatID — day chinh la cau noi ma SP nay bo sung.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @s2  INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID <> @s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT, @ts2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR OK'', @NewVenueTemplateID=@vt OUTPUT;
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
         @ConcertName=N''REG AESFMR OK Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    DECLARE @cmrs2 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s2);
    DECLARE @csv NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12)) + N'','' + CAST(@cmrs2 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv;

    IF (SELECT COUNT(*) FROM EventSeat WHERE ConcertID=@cid) <> 2
        THROW 59999, ''Phai tao dung 2 EventSeat'', 1;
    IF EXISTS (SELECT 1 FROM EventSeat WHERE ConcertID=@cid AND (SalePrice <> 250000 OR InventoryStatus <> ''Available''))
        THROW 59999, ''SalePrice phai lay tu BasePrice va InventoryStatus phai la Available'', 1;
    IF EXISTS (SELECT 1 FROM ConcertMapRevisionSeat WHERE ConcertMapRevisionSeatID IN (@cmrs1, @cmrs2) AND EventSeatID IS NULL)
        THROW 59999, ''ConcertMapRevisionSeat.EventSeatID phai duoc ghi nguoc sau khi them vao kho ve'', 1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_OK','SUCCESS',NULL,@SQL;

-- Revision con Draft (chua Lock) — CHI duoc dua ghe tu revision da Locked.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR Draft'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR Draft Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_RevisionNotLocked_Fail60242','ERROR',60242,@SQL;

-- Revision khong ton tai.
SET @SQL = N'
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cat INT = (SELECT TOP 1 TicketCategoryID FROM TicketCategory);
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=-1, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=N''1'';';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_RevisionNotExist_Fail60241','ERROR',60241,@SQL;

-- Actor khong phai Organizer cua Concert cung khong phai Admin.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR NotOwner'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR NotOwner Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@cust, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_NotOwnerNotAdmin_Fail60243','ERROR',60243,@SQL;

-- Concert khong con Draft/Published (BP3) — thao tac tho de dat toi trang thai
-- Cancelled sau khi da Lock revision (khong the dat toi qua luong SP binh thuong
-- vi Cancel that su can di qua sp_CancelBooking/refund; kiem tra phong thu SP).
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR BP3'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR BP3 Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;
    UPDATE Concert SET ConcertStatus = ''Cancelled'' WHERE ConcertID = @cid;

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_ConcertNotSellable_Fail60244','ERROR',60244,@SQL;

-- TicketCategory khong Active.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR CatInactive'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR CatInactive Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @CategoryStatus=''Inactive'', @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_CategoryNotActive_Fail60245','ERROR',60245,@SQL;

-- Danh sach ghe rong.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR Empty'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR Empty Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;

    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=N''  '';';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_EmptyList_Fail60246','ERROR',60246,@SQL;

-- Ghe khong thuoc revision nay (id bia dat).
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR Foreign'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR Foreign Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;

    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=N''-1'';';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_SeatNotInRevision_Fail60247','ERROR',60247,@SQL;

-- Ghe da duoc dua vao kho ve tu truoc (goi SP hai lan cho cung mot ghe).
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR Dup'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR Dup Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_AlreadyLinked_Fail60248','ERROR',60248,@SQL;

-- BR50e: Seat da Retired khong duoc dua vao kho ve moi.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR Retired'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR Retired Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;
    UPDATE Seat SET SeatStatus = ''Retired'' WHERE SeatID = @s1;

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_SeatRetired_Fail60249','ERROR',60249,@SQL;

-- DR-08: Seat da co trong kho ve cua CHINH Concert nay tu nguon khac (them qua
-- sp_AddEventSeats/Zone truoc, roi thu them lai chinh Seat do qua StagePass).
-- LUU Y: sp_CreateConcertMap gio tu choi tao map khi Concert DA co EventSeat
-- legacy (60205), VA sp_AddEventSeats gio tu choi them EventSeat legacy khi
-- Concert DA co ConcertMap (58221) — hai chieu khoa lan nhau nay lam kich ban
-- goc (goi sp_AddEventSeats TRUOC roi sp_CreateConcertMap SAU) khong con dat
-- toi duoc qua SP theo BAT KY thu tu nao. De giu nguyen y do DR-08 (mot Seat
-- da co trong EventSeat cua Concert tu nguon khac truoc khi dua vao qua
-- StagePass), doi thu tu (Map/Revision/Lock TRUOC) roi INSERT THANG vao
-- EventSeat (bypass sp_AddEventSeats) de mo phong du lieu legacy da ton tai
-- tu truoc rang buoc loai tru lan nhau nay — cung ky thuat thao tac tho da
-- dung xuyen suot bo test cho cac bat bien khong dat toi duoc qua SP.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AESFMR DR08'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG AESFMR DR08 Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid, @CategoryName=N''VIP'',
         @CategoryDescription=N''d'', @BasePrice=250000, @TicketCategoryID=@cat OUTPUT;

    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    DECLARE @cmr INT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;

    INSERT INTO EventSeat (ConcertID, SeatID, TicketCategoryID, SalePrice, InventoryStatus, AddedTimestamp)
    VALUES (@cid, @s1, @cat, 250000, ''Available'', SYSDATETIME());

    DECLARE @cmrs1 INT = (SELECT ConcertMapRevisionSeatID FROM ConcertMapRevisionSeat WHERE SeatID=@s1);
    DECLARE @csv1 NVARCHAR(64) = CAST(@cmrs1 AS NVARCHAR(12));
    EXEC dbo.sp_AddEventSeatsFromMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr, @TicketCategoryID=@cat, @ConcertMapRevisionSeatIDs=@csv1;';
EXEC test.sp_RunTest @Suite,'AddEventSeatsFromMapRevision_SeatAlreadyInConcertEventSeat_Fail60250','ERROR',60250,@SQL;
