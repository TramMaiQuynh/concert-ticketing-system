-- ============================================================
-- 15_Test_StagePass_Schema.sql
-- Kiem chung 12 bang moi cua lop StagePass (xem docs/stagepass-architecture.md):
--   VenueTemplate, VenueTemplateVersion, TemplateFloor, TemplateObject,
--   TemplateSection, TemplateSeat, ConcertMap, ConcertMapRevision,
--   ConcertMapRevisionFloor/Object/Section/Seat.
--
-- Chua co tang Stored Procedure cho nhom bang nay (dang xay dung), nen test o
-- day kiem CHECK/UNIQUE/FK truc tiep bang INSERT tho, cung khuon
-- 02_Test_Tables_Constraints.sql. Khi co SP thay the, bo sung file rieng kiem
-- qua SP (cung khuon 12_Test_SP_AdminAndCatalog.sql).
--
-- Dung du lieu mock co san (01_SetupMockData.sql): test_admin, test_org, mot
-- Concert OnSale, mot Seat da co vi tri.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StagePass_Schema';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- 1. Duong hanh phuc: chen du toan bo chuoi 12 bang phai THANH CONG
-- ============================================================
SET @SQL = N'
    DECLARE @adm  INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven  INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @cid  INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @s1   INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT;
    DECLARE @cm INT, @cmr INT, @cmrf INT, @cmrs INT;

    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG Theatre'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    SET @vtv = SCOPE_IDENTITY();
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateObject (TemplateFloorID, ObjectType, GeometryJson)
    VALUES (@fl, ''Stage'', N''{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}'');
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":100,"y":150,"width":300,"height":200,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''S1'', N''A'', 1);
    SET @ts1 = SCOPE_IDENTITY();

    INSERT INTO ConcertMap (ConcertID) VALUES (@cid);
    SET @cm = SCOPE_IDENTITY();
    INSERT INTO ConcertMapRevision (ConcertMapID, SourceVenueTemplateVersionID, RevisionNumber, RevisionStatus)
    VALUES (@cm, @vtv, 1, ''Draft'');
    SET @cmr = SCOPE_IDENTITY();
    INSERT INTO ConcertMapRevisionFloor (ConcertMapRevisionID, SourceTemplateFloorID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@cmr, @fl, ''ground'', 1, 1000, 800);
    SET @cmrf = SCOPE_IDENTITY();
    INSERT INTO ConcertMapRevisionObject (ConcertMapRevisionFloorID, ObjectType, GeometryJson)
    VALUES (@cmrf, ''Stage'', N''{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}'');
    INSERT INTO ConcertMapRevisionSection (ConcertMapRevisionFloorID, SourceTemplateSectionID, SectionKey, GeometryJson)
    VALUES (@cmrf, @sec, ''VIP'', N''{"version":1,"shape":"rect","x":100,"y":150,"width":300,"height":200,"rotation":0}'');
    SET @cmrs = SCOPE_IDENTITY();
    -- Hai dong EventSeatID = NULL trong CUNG mot Section: day chinh la kich ban
    -- da phat hien bug UQ_CMRSeat_EventSeat (SQL Server coi hai NULL la trung
    -- nhau trong UNIQUE constraint thuong). Neu regression quay lai, dong INSERT
    -- thu hai se nem loi va test nay do.
    INSERT INTO ConcertMapRevisionSeat (ConcertMapRevisionSectionID, SourceTemplateSeatID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@cmrs, @ts1, @s1, ''S1'', N''A'', 1);
    DECLARE @s2 INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID <> @s1);
    IF @s2 IS NOT NULL
        INSERT INTO ConcertMapRevisionSeat (ConcertMapRevisionSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
        VALUES (@cmrs, @s2, ''S2'', N''A'', 2);';
EXEC test.sp_RunTest @Suite,'FullChain_TwelveTablesInsert_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 2. UIX_VTV_OneDraftPerTemplate: hai Draft cho cung Template -> loi
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT;
    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG TwoDrafts'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 2, ''Draft'', @adm);';
EXEC test.sp_RunTest @Suite,'VenueTemplateVersion_TwoDrafts_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 3. CHK_VTV_PublishedTimestamp: Published thieu moc thoi gian -> loi
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT;
    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG PubNoTime'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID, PublishedTimestamp)
    VALUES (@vt, 1, ''Published'', @adm, NULL);';
EXEC test.sp_RunTest @Suite,'VenueTemplateVersion_PublishedNoTimestamp_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 4. UIX_TemplateSeat_GridSlot: trung o luoi trong cung Section -> loi
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG GridDup'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    SET @vtv = SCOPE_IDENTITY();
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''A1'', N''A'', 1);
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''A1-DUP'', N''A'', 1);';
EXEC test.sp_RunTest @Suite,'TemplateSeat_DuplicateGridSlot_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 5. CHK_TemplateSeat_RowNumberTogether: co hang khong co so -> loi
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG RowHalf'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    SET @vtv = SCOPE_IDENTITY();
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''A1'', N''A'', NULL);';
EXEC test.sp_RunTest @Suite,'TemplateSeat_RowWithoutNumber_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 6. CHK_TemplateSection_GeometryJson: JSON hong -> loi
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT;
    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG BadJson'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    SET @vtv = SCOPE_IDENTITY();
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''BAD'', N''{not valid json'');';
EXEC test.sp_RunTest @Suite,'TemplateSection_InvalidGeometryJson_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 7. UQ_ConcertMap_Concert: hai ConcertMap cho cung Concert -> loi
-- ============================================================
SET @SQL = N'
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    INSERT INTO ConcertMap (ConcertID) VALUES (@cid);
    INSERT INTO ConcertMap (ConcertID) VALUES (@cid);';
EXEC test.sp_RunTest @Suite,'ConcertMap_DuplicateConcert_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 8. UIX_CMR_OneLockedPerMap: hai revision Locked cung mot Map -> loi
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @cid INT = (SELECT TOP 1 ConcertID FROM Concert);
    DECLARE @vt INT, @vtv INT, @cm INT;
    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG TwoLocked'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    SET @vtv = SCOPE_IDENTITY();
    INSERT INTO ConcertMap (ConcertID) VALUES (@cid);
    SET @cm = SCOPE_IDENTITY();
    INSERT INTO ConcertMapRevision (ConcertMapID, SourceVenueTemplateVersionID, RevisionNumber, RevisionStatus, LockedTimestamp)
    VALUES (@cm, @vtv, 1, ''Locked'', SYSDATETIME());
    INSERT INTO ConcertMapRevision (ConcertMapID, SourceVenueTemplateVersionID, RevisionNumber, RevisionStatus, LockedTimestamp)
    VALUES (@cm, @vtv, 2, ''Locked'', SYSDATETIME());';
EXEC test.sp_RunTest @Suite,'ConcertMapRevision_TwoLockedForSameMap_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 9. UIX_CMRSeat_EventSeat: hai ConcertMapRevisionSeat tro cung mot EventSeat -> loi
--    Dung EventSeat THAT qua sp_AddEventSeats de dung nguyen luong nghiep vu,
--    khong INSERT thang vao EventSeat (bang do bi DENY ghi truc tiep voi
--    api_service trong production - dung sqlcmd/dbo o day la boi canh test).
--
--    Tu dung Concert RIENG o trang thai Draft, khong dung Concert mock dung
--    chung: Concert mock (01_SetupMockData.sql) da o trang thai OnSale, va
--    sp_AddEventSeats chi nhan Concert Draft/Published (58218) - dung chung se
--    lam test that bai vi mot ly do KHAC voi dieu dang kiem, y het cai bay da
--    gap va sua ngay ben tren (bien @cmrf khai bao trung).
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @org INT = (SELECT UserID FROM UserAccount WHERE Username=''test_org'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @art INT = (SELECT TOP 1 ArtistID FROM Artist);
    DECLARE @cid INT;
    DECLARE @artJson NVARCHAR(64) = N''['' + CAST(@art AS NVARCHAR(12)) + N'']'';
    -- DATEADD(day,...) khong duoc dung TRUC TIEP lam gia tri tham so dat ten
    -- trong EXEC (loi 102 "Incorrect syntax near ''day''" — tu khoa khoang
    -- thoi gian khong dau nhay gay nhap nhang cho parser cua EXEC voi cu
    -- phap @param=<bieu thuc>, khac han DECLARE/SET binh thuong). Phai tinh
    -- truoc vao bien roi moi truyen bien — dung bai hoc da rut ra truoc do
    -- trong chinh phien lam viec nay ("Hai loi T-SQL bieu thuc lam tham so
    -- EXEC — sua bang bien tinh truoc").
    DECLARE @StartDT DATETIME2(7) = DATEADD(day, 30, SYSDATETIME());
    DECLARE @EndDT   DATETIME2(7) = DATEADD(day, 31, SYSDATETIME());
    EXEC dbo.sp_CreateConcert @OrganizerUserID=@org, @ArtistIDs=@artJson, @VenueID=@ven,
         @ConcertName=N''REG DupEventSeat Concert'',
         @StartDatetime=@StartDT, @EndDatetime=@EndDT,
         @SaleStartDatetime=NULL, @SaleEndDatetime=NULL, @PurchaseLimit=4,
         @TemporaryHoldDuration=900, @CancellationPolicy=NULL, @RefundPolicy=NULL,
         @ActorUserID=@org, @NewConcertID=@cid OUTPUT;
    DECLARE @cat INT;
    EXEC dbo.sp_ConfigureTicketCategory @ActorUserID=@org, @ConcertID=@cid,
         @CategoryName=N''Thuong'', @CategoryDescription=NULL, @BasePrice=100000,
         @TicketCategoryID=@cat OUTPUT;
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID NOT IN (SELECT SeatID FROM EventSeat WHERE ConcertID=@cid));
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @cm INT, @cmr INT, @cmrs INT;

    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG DupEventSeat'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    SET @vtv = SCOPE_IDENTITY();
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();

    INSERT INTO ConcertMap (ConcertID) VALUES (@cid);
    SET @cm = SCOPE_IDENTITY();
    INSERT INTO ConcertMapRevision (ConcertMapID, SourceVenueTemplateVersionID, RevisionNumber, RevisionStatus)
    VALUES (@cm, @vtv, 1, ''Draft'');
    SET @cmr = SCOPE_IDENTITY();
    INSERT INTO ConcertMapRevisionFloor (ConcertMapRevisionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@cmr, ''ground'', 1, 1000, 800);
    DECLARE @cmrf INT = SCOPE_IDENTITY();
    INSERT INTO ConcertMapRevisionSection (ConcertMapRevisionFloorID, SectionKey, GeometryJson)
    VALUES (@cmrf, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @cmrs = SCOPE_IDENTITY();

    EXEC dbo.sp_AddEventSeats @ActorUserID=@org, @ConcertID=@cid, @TicketCategoryID=@cat, @SeatIDs=@s1;
    DECLARE @es INT = (SELECT EventSeatID FROM EventSeat WHERE ConcertID=@cid AND SeatID=@s1);

    INSERT INTO ConcertMapRevisionSeat (ConcertMapRevisionSectionID, SeatID, SeatKey, RowLabel, SeatNumber, EventSeatID)
    VALUES (@cmrs, @s1, ''X1'', N''A'', 1, @es);
    INSERT INTO ConcertMapRevisionSeat (ConcertMapRevisionSectionID, SeatID, SeatKey, RowLabel, SeatNumber, EventSeatID)
    VALUES (@cmrs, @s1, ''X2'', N''A'', 2, @es);';
EXEC test.sp_RunTest @Suite,'ConcertMapRevisionSeat_DuplicateEventSeat_Fail','ERROR',NULL,@SQL;

-- ============================================================
-- 10. RowVer tu doi khi UPDATE — dieu kien can de ETag co y nghia
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT;
    INSERT INTO VenueTemplate (VenueID, TemplateName) VALUES (@ven, N''REG RowVer'');
    SET @vt = SCOPE_IDENTITY();
    INSERT INTO VenueTemplateVersion (VenueTemplateID, VersionNumber, VersionStatus, AuthorUserID)
    VALUES (@vt, 1, ''Draft'', @adm);
    SET @vtv = SCOPE_IDENTITY();
    DECLARE @rv1 VARBINARY(8) = (SELECT RowVer FROM VenueTemplateVersion WHERE VenueTemplateVersionID=@vtv);
    UPDATE VenueTemplateVersion SET AuthorUserID = @adm WHERE VenueTemplateVersionID=@vtv;
    DECLARE @rv2 VARBINARY(8) = (SELECT RowVer FROM VenueTemplateVersion WHERE VenueTemplateVersionID=@vtv);
    IF @rv1 = @rv2
        THROW 59999, ''RowVer khong doi sau UPDATE'', 1;';
EXEC test.sp_RunTest @Suite,'VenueTemplateVersion_RowVerChangesOnUpdate_OK','SUCCESS',NULL,@SQL;
