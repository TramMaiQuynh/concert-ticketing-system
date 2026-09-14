-- ============================================================
-- 22_Test_Regression_SessionFixes.sql
-- Test hoi quy cho cac lo hong duoc phat hien va sua trong dot ra soat theo
-- bao cao 20-muc (Venue/Zone/Seat/Template lifecycle, luat OnSale/StagePass,
-- integrity snapshot, input CSV). Cung khuon 13_Test_Regression_Fixes.sql:
-- moi test tuong ung MOT lo hong that da xac minh truoc khi sua.
--
-- Du lieu mock (01_SetupMockData): test_admin (Admin), test_org (Organizer),
-- mot Venue Active co Zone VIP (co ghe) va GA (khong ghe), mot Artist Active.
-- ============================================================
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'Regression_SessionFixes';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- 1. sp_CreateConcert tu choi Venue Inactive (58009)
-- ============================================================
SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist WHERE ArtistStatus=''Active'');
    DECLARE @ven INT;
    INSERT INTO Venue (VenueName, VenueStatus) VALUES (N''REG InactiveVenueCreate'', ''Inactive'');
    SET @ven = SCOPE_IDENTITY();
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG Inactive Venue'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateConcert_InactiveVenue_Fail58009','ERROR',58009,@SQL;

-- ============================================================
-- 2. sp_CreateVenueTemplate tu choi Venue Inactive (60097)
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT;
    INSERT INTO Venue (VenueName, VenueStatus) VALUES (N''REG InactiveVenueTemplate'', ''Inactive'');
    SET @ven = SCOPE_IDENTITY();
    DECLARE @vt INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG X'', @NewVenueTemplateID=@vt OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateVenueTemplate_InactiveVenue_Fail60097','ERROR',60097,@SQL;

-- ============================================================
-- 3. sp_UpdateConcert: doi sang Venue Inactive bi tu choi (58027)
-- ============================================================
SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist WHERE ArtistStatus=''Active'');
    DECLARE @ven1 INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @ven2 INT;
    INSERT INTO Venue (VenueName, VenueStatus) VALUES (N''REG InactiveVenueUpdate'', ''Inactive'');
    SET @ven2 = SCOPE_IDENTITY();
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven1,
         @ConcertName=N''REG UpdVenueInactive'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    EXEC dbo.sp_UpdateConcert @ConcertID=@cid, @ActorUserID=@org, @VenueID=@ven2;';
EXEC test.sp_RunTest @Suite,'UpdateConcert_ChangeToInactiveVenue_Fail58027','ERROR',58027,@SQL;

-- ============================================================
-- 4. sp_UpdateConcert: doi Venue khi Concert da co ConcertMap bi tu choi (58028)
--    Truoc ban sua nay, khong co kiem tra nao — Venue doi tu do, trong khi
--    ConcertMap/snapshot van tro toi VenueTemplate cua Venue CU.
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist WHERE ArtistStatus=''Active'');
    DECLARE @ven1 INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @ven2 INT;
    INSERT INTO Venue (VenueName, VenueStatus) VALUES (N''REG VenueChangeTarget'', ''Active'');
    SET @ven2 = SCOPE_IDENTITY();
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven1,
         @ConcertName=N''REG VenueChangeWithMap'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    EXEC dbo.sp_UpdateConcert @ConcertID=@cid, @ActorUserID=@org, @VenueID=@ven2;';
EXEC test.sp_RunTest @Suite,'UpdateConcert_ChangeVenueWithConcertMap_Fail58028','ERROR',58028,@SQL;

-- ============================================================
-- 5. TRG_ConcertVenueChangeGuard: ghi truc tiep (bo qua SP) doi VenueID khi
--    da co ConcertMap van bi chan (50132) — lop phong thu chieu sau.
-- ============================================================
SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist WHERE ArtistStatus=''Active'');
    DECLARE @ven1 INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @ven2 INT;
    INSERT INTO Venue (VenueName, VenueStatus) VALUES (N''REG VenueChangeDirect'', ''Active'');
    SET @ven2 = SCOPE_IDENTITY();
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven1,
         @ConcertName=N''REG VenueChangeDirectConcert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cm INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    UPDATE Concert SET VenueID=@ven2 WHERE ConcertID=@cid;';
EXEC test.sp_RunTest @Suite,'TRGConcertVenueChangeGuard_DirectWriteWithMap_Fail50132','ERROR',50132,@SQL;

-- ============================================================
-- 6. sp_UpdateZone: khong Retire duoc Zone dang duoc VenueTemplateVersion DA
--    PUBLISH tham chieu (59416). Truoc ban sua: Zone Retire duoc im lang, loi
--    chi lo ra rat muon (60249) luc dua ghe vao kho ve.
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @zn INT;
    INSERT INTO Zone (VenueID, ZoneCode, ZoneName) VALUES (@ven, N''REGZ1'', N''REG Zone For Template'');
    SET @zn = SCOPE_IDENTITY();
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG ZoneRetireBlock'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    DECLARE @s1 INT;
    INSERT INTO Seat (ZoneID, VenueID, SeatCode) VALUES (@zn, @ven, N''REGZ1-A1'');
    SET @s1 = SCOPE_IDENTITY();
    DECLARE @ts1 INT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_UpdateZone @ActorUserID=@adm, @ZoneID=@zn, @ZoneStatus=N''Retired'';';
EXEC test.sp_RunTest @Suite,'UpdateZone_RetireReferencedByPublishedTemplate_Fail59416','ERROR',59416,@SQL;

-- ============================================================
-- 7. sp_UpdateSeat: khong Retire duoc Seat dang duoc VenueTemplateVersion DA
--    PUBLISH tham chieu (59426).
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @zn INT;
    INSERT INTO Zone (VenueID, ZoneCode, ZoneName) VALUES (@ven, N''REGZ2'', N''REG Zone For Seat Retire'');
    SET @zn = SCOPE_IDENTITY();
    DECLARE @s1 INT;
    INSERT INTO Seat (ZoneID, VenueID, SeatCode) VALUES (@zn, @ven, N''REGZ2-A1'');
    SET @s1 = SCOPE_IDENTITY();
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SeatRetireBlock'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_UpdateSeat @ActorUserID=@adm, @SeatID=@s1, @SeatStatus=N''Retired'';';
EXEC test.sp_RunTest @Suite,'UpdateSeat_RetireReferencedByPublishedTemplate_Fail59426','ERROR',59426,@SQL;

-- ============================================================
-- 8. sp_ConfigureTemplateSection: khong doi ZoneID duoc khi Section da co ghe
--    (60098). Truoc ban sua: ZoneID doi tu do, de lai ghe cu "nam trong" mot
--    Section gio dai dien cho Zone khac.
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @znA INT, @znB INT;
    INSERT INTO Zone (VenueID, ZoneCode, ZoneName) VALUES (@ven, N''REGZA'', N''REG Zone A''), (@ven, N''REGZB'', N''REG Zone B'');
    SET @znA = (SELECT ZoneID FROM Zone WHERE VenueID=@ven AND ZoneCode=N''REGZA'');
    SET @znB = (SELECT ZoneID FROM Zone WHERE VenueID=@ven AND ZoneCode=N''REGZB'');
    DECLARE @s1 INT;
    INSERT INTO Seat (ZoneID, VenueID, SeatCode) VALUES (@znA, @ven, N''REGZA-A1'');
    SET @s1 = SCOPE_IDENTITY();
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SectionZoneLock'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@znA, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateSectionID=@sec, @TemplateFloorID=@fl, @ZoneID=@znB, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'';';
EXEC test.sp_RunTest @Suite,'ConfigureTemplateSection_ChangeZoneWithSeats_Fail60098','ERROR',60098,@SQL;

-- Doi chieu: Section RONG (chua co ghe) van doi ZoneID tu do duoc — dung 1
-- Zone / 1 Section moi phia tren khong bi khoa oan.
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @znA INT, @znB INT;
    INSERT INTO Zone (VenueID, ZoneCode, ZoneName) VALUES (@ven, N''REGZC'', N''REG Zone C''), (@ven, N''REGZD'', N''REG Zone D'');
    SET @znA = (SELECT ZoneID FROM Zone WHERE VenueID=@ven AND ZoneCode=N''REGZC'');
    SET @znB = (SELECT ZoneID FROM Zone WHERE VenueID=@ven AND ZoneCode=N''REGZD'');
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SectionZoneFree'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@znA, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateSectionID=@sec, @TemplateFloorID=@fl, @ZoneID=@znB, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'';
    IF (SELECT ZoneID FROM TemplateSection WHERE TemplateSectionID=@sec) <> @znB
        THROW 59999, ''Section rong phai doi ZoneID tu do duoc'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureTemplateSection_ChangeZoneNoSeats_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 9. sp_ProcessSaleWindowTransitions: Concert dung StagePass nhung co MOT
--    EventSeat khong khop voi revision Locked (vd. ghi truc tiep, bo qua
--    sp_AddEventSeatsFromMapRevision — duong DUY NHAT hop le de gan EventSeat
--    mot khi da co ConcertMap, theo dung mutual-exclusion 60205/58221) khong
--    duoc tu dong len OnSale — bi loc khoi lo, o lai Published. Truoc ban sua,
--    job nay chi kiem BR10 (co EventSeat), bo qua hoan toan dieu kien nay.
--
--    Luu y ve pham vi: mutual-exclusion 60205 (sp_CreateConcertMap tu choi
--    neu da co EventSeat legacy) va 58221 (sp_AddEventSeats tu choi neu da co
--    ConcertMap) da co TRUOC dot sua nay, nen mot khi Concert co ConcertMap,
--    duong SP hop le DUY NHAT de co EventSeat la sp_AddEventSeatsFromMapRevision
--    — luon doi hoi revision Locked va luon lien ket dung trong cung transaction.
--    Vi vay kich ban "co EventSeat le" chi tai hien duoc bang ghi truc tiep
--    (mo phong mot duong ghi khac/tuong lai, hoac loi thao tac cua admin), dung
--    khuon ma cac test file 15/16/18-21 da dung cho cac bat bien tuong tu.
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist WHERE ArtistStatus=''Active'');
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @s1 INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG AutoOnSaleGuard'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @art2 NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    DECLARE @SaleStart DATETIME2(7) = DATEADD(minute, -5, SYSDATETIME());
    DECLARE @SaleEnd   DATETIME2(7) = DATEADD(day, 29, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@art2, @VenueID=@ven,
         @ConcertName=N''REG AutoOnSaleBlockedByMap'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=@SaleStart, @SaleEndDatetime=@SaleEnd, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    EXEC dbo.sp_UpdateConcertStatus @ConcertID=@cid, @ActorUserID=@org, @NewStatus=N''Published'';
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid,
         @CategoryName=N''Thuong'', @CategoryDescription=NULL, @BasePrice=100000, @TicketCategoryID=@cat OUTPUT;

    DECLARE @cm INT, @cmr INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    EXEC dbo.sp_LockConcertMapRevision @ActorUserID=@org, @ConcertMapRevisionID=@cmr;
    -- Ghi truc tiep MOT EventSeat KHONG qua sp_AddEventSeatsFromMapRevision —
    -- mo phong mot ghe "le", khong duoc revision Locked biet den.
    INSERT INTO EventSeat (ConcertID, SeatID, TicketCategoryID, SalePrice, InventoryStatus, AddedTimestamp)
    VALUES (@cid, @s1, @cat, 100000, N''Available'', SYSDATETIME());

    EXEC dbo.sp_ProcessSaleWindowTransitions;
    IF (SELECT ConcertStatus FROM Concert WHERE ConcertID=@cid) <> N''Published''
        THROW 59999, ''Concert co EventSeat khong khop revision Locked khong duoc tu dong len OnSale'', 1;';
EXEC test.sp_RunTest @Suite,'ProcessSaleWindowTransitions_InconsistentMapSeat_StaysPublished_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 10. TRG_CMRSeat_EventSeatConsistency: ghi truc tiep EventSeatID sai Concert
--    vao ConcertMapRevisionSeat bi chan (50140). Truoc ban sua: bat bien nay
--    chi duoc thi hanh boi sp_AddEventSeatsFromMapRevision — mot UPDATE truc
--    tiep (vd. app_admin) khong bi chan o dau ca.
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT=(SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist WHERE ArtistStatus=''Active'');
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @s1 INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG CMRSeatGuard'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;

    DECLARE @art2 NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@art2, @VenueID=@ven,
         @ConcertName=N''REG CMRSeatGuard Concert'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid,
         @CategoryName=N''Thuong'', @CategoryDescription=NULL, @BasePrice=100000, @TicketCategoryID=@cat OUTPUT;
    DECLARE @s2 INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID <> @s1);
    -- EventSeat nay thuoc mot Concert KHAC (mock concert co san), khong phai @cid.
    DECLARE @otherCid INT = (SELECT TOP 1 ConcertID FROM Concert WHERE ConcertID <> @cid);
    DECLARE @wrongEs INT = (SELECT TOP 1 EventSeatID FROM EventSeat WHERE ConcertID = @otherCid);
    IF @wrongEs IS NULL
    BEGIN
        DECLARE @cat2 INT;
        EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@otherCid,
             @CategoryName=N''REG Filler'', @CategoryDescription=NULL, @BasePrice=50000, @TicketCategoryID=@cat2 OUTPUT;
        DECLARE @sFiller INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID NOT IN (SELECT SeatID FROM EventSeat WHERE ConcertID=@otherCid));
        DECLARE @sFillerCsv NVARCHAR(12) = CAST(@sFiller AS NVARCHAR(12));
        EXEC dbo.sp_AddEventSeats @ActorUserID=@org, @ConcertID=@otherCid, @TicketCategoryID=@cat2, @SeatIDs=@sFillerCsv;
        SET @wrongEs = (SELECT EventSeatID FROM EventSeat WHERE ConcertID=@otherCid AND SeatID=@sFiller);
    END

    DECLARE @cm INT, @cmr INT;
    EXEC dbo.sp_CreateConcertMap @ActorUserID=@org, @ConcertID=@cid, @NewConcertMapID=@cm OUTPUT;
    EXEC dbo.sp_CreateConcertMapRevision @ActorUserID=@org, @ConcertMapID=@cm, @SourceVenueTemplateVersionID=@vtv, @NewConcertMapRevisionID=@cmr OUTPUT;
    DECLARE @cmrs INT = (SELECT cs.ConcertMapRevisionSeatID
                         FROM ConcertMapRevisionSeat cs
                         JOIN ConcertMapRevisionSection sec2 ON sec2.ConcertMapRevisionSectionID = cs.ConcertMapRevisionSectionID
                         JOIN ConcertMapRevisionFloor fl2 ON fl2.ConcertMapRevisionFloorID = sec2.ConcertMapRevisionFloorID
                         WHERE fl2.ConcertMapRevisionID = @cmr);
    -- Ghi truc tiep EventSeatID cua mot Concert KHAC vao map-seat cua @cid.
    UPDATE ConcertMapRevisionSeat SET EventSeatID = @wrongEs WHERE ConcertMapRevisionSeatID = @cmrs;';
EXEC test.sp_RunTest @Suite,'TRGCMRSeatConsistency_WrongConcertEventSeat_Fail50140','ERROR',50140,@SQL;

-- ============================================================
-- 11. Danh sach CSV chua gia tri khong phai so nguyen -> loi nghiep vu ro
--    rang, khong con loi chuyen doi SQL tho.
-- ============================================================
SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @art INT=(SELECT TOP 1 ArtistID FROM Artist WHERE ArtistStatus=''Active'');
    DECLARE @ven INT=(SELECT TOP 1 VenueID FROM Venue WHERE VenueStatus=''Active'');
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    DECLARE @cid INT;
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG BadCsv'', @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4, @TemporaryHoldDuration=900,
         @CancellationPolicy=NULL, @RefundPolicy=NULL, @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid,
         @CategoryName=N''Thuong'', @CategoryDescription=NULL, @BasePrice=100000, @TicketCategoryID=@cat OUTPUT;
    EXEC dbo.sp_AddEventSeats @ActorUserID=@org, @ConcertID=@cid, @TicketCategoryID=@cat, @SeatIDs=N''1,abc'';';
EXEC test.sp_RunTest @Suite,'AddEventSeats_MalformedSeatIdCsv_Fail58222','ERROR',58222,@SQL;

SET @SQL = N'
    DECLARE @org INT=(SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @cid INT=(SELECT TOP 1 ConcertID FROM Concert);
    EXEC dbo.sp_AddCheckinStaffAssignment @ActorUserID=@org, @ConcertIDs=N''1,x'', @StaffUserID=999999, @AssignmentStatus=N''Active'';';
EXEC test.sp_RunTest @Suite,'AddCheckinStaffAssignment_MalformedConcertIdCsv_Fail59006','ERROR',59006,@SQL;

PRINT N'22_Test_Regression_SessionFixes: hoan tat.';
