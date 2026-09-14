-- ============================================================
-- 16_Test_StagePass_TemplateLifecycle.sql
-- Kiem chung 4 SP vong doi VenueTemplate/VenueTemplateVersion (StagePass D.2):
--   sp_CreateVenueTemplate, sp_CreateVenueTemplateVersion,
--   sp_PublishVenueTemplateVersion, sp_DeleteVenueTemplateVersionDraft.
-- Cung khuon 12_Test_SP_AdminAndCatalog.sql (goi qua SP, khong INSERT tho).
-- Dung mock co san: test_admin (Admin), test_cust1 (Customer, dung lam actor
-- KHONG co quyen), mot Venue, it nhat hai Seat.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StagePass_TemplateLifecycle';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- 1. sp_CreateVenueTemplate: duong hanh phuc
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt  INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Theatre'', @NewVenueTemplateID=@vt OUTPUT;
    IF @vt IS NULL THROW 59999, ''NewVenueTemplateID khong duoc gan'', 1;';
EXEC test.sp_RunTest @Suite,'CreateVenueTemplate_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 2. sp_CreateVenueTemplate: actor khong phai Admin -> 60001
-- ============================================================
SET @SQL = N'
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@cust, @VenueID=@ven, @TemplateName=N''REG NotAdmin'', @NewVenueTemplateID=@vt OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateVenueTemplate_NotAdmin_Fail60001','ERROR',60001,@SQL;

-- ============================================================
-- 3. sp_CreateVenueTemplate: trung ten trong cung Venue -> 60004
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt1 INT, @vt2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DupName'', @NewVenueTemplateID=@vt1 OUTPUT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DupName'', @NewVenueTemplateID=@vt2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateVenueTemplate_DuplicateName_Fail60004','ERROR',60004,@SQL;

-- ============================================================
-- 4. sp_CreateVenueTemplateVersion: duong hanh phuc, VersionNumber = 1
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG V1'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    IF (SELECT VersionNumber FROM VenueTemplateVersion WHERE VenueTemplateVersionID=@vtv) <> 1
        THROW 59999, ''VersionNumber dau tien phai la 1'', 1;';
EXEC test.sp_RunTest @Suite,'CreateVenueTemplateVersion_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 5. sp_CreateVenueTemplateVersion: da co Draft mo -> 60014
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv1 INT, @vtv2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG TwoDraftsSP'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv1 OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'CreateVenueTemplateVersion_DraftAlreadyOpen_Fail60014','ERROR',60014,@SQL;

-- ============================================================
-- 6. sp_PublishVenueTemplateVersion: version rong (khong ghe) -> 60024
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Empty'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;';
EXEC test.sp_RunTest @Suite,'PublishVenueTemplateVersion_Empty_Fail60024','ERROR',60024,@SQL;

-- ============================================================
-- 7. sp_PublishVenueTemplateVersion: duong hanh phuc, sau do publish lan hai -> 60023
--    QUAN TRONG: sp_RunTest luon ROLLBACK sau MOI lan goi (xem 00_TestFramework.sql),
--    nen du lieu tao trong mot test KHONG con cho test sau doc — moi test phai
--    tu dung du lieu cua chinh no trong CUNG mot @SQL. Day chinh la cai bay da
--    gap va sua o test #9 cua 15_Test_StagePass_Schema.sql, lap lai o day cho ca
--    ba test 7 ben duoi (da tung viet sai theo huong "tai su dung du lieu test
--    truoc", chay that moi phat hien vi khong co ROLLBACK nao lo dieu do ra).
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG Publish'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''S1'', N''A'', 1);
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    IF (SELECT VersionStatus FROM VenueTemplateVersion WHERE VenueTemplateVersionID=@vtv) <> ''Published''
        THROW 59999, ''VersionStatus phai la Published sau khi publish'', 1;
    IF (SELECT PublishedTimestamp FROM VenueTemplateVersion WHERE VenueTemplateVersionID=@vtv) IS NULL
        THROW 59999, ''PublishedTimestamp khong duoc NULL sau khi publish'', 1;';
EXEC test.sp_RunTest @Suite,'PublishVenueTemplateVersion_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG PublishTwice'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''S1'', N''A'', 1);
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;';
EXEC test.sp_RunTest @Suite,'PublishVenueTemplateVersion_AlreadyPublished_Fail60023','ERROR',60023,@SQL;

-- ============================================================
-- 8. sp_CreateVenueTemplateVersion voi @CopyFromVersionID: sao chep dung so luong
--    Floor/Section/Seat tu version nguon — tu dung Template/Version/Floor/
--    Section/Seat cua chinh no roi Publish ngay trong cung @SQL (xem ly do o
--    comment truoc test 7).
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @srcVtv INT, @fl INT, @sec INT, @newVtv INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG CopyFrom'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@srcVtv OUTPUT;
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@srcVtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''S1'', N''A'', 1);
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@srcVtv;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @CopyFromVersionID=@srcVtv, @NewVenueTemplateVersionID=@newVtv OUTPUT;
    IF (SELECT COUNT(*) FROM TemplateFloor WHERE VenueTemplateVersionID=@newVtv) <> 1
        THROW 59999, ''Phai sao chep dung 1 Floor'', 1;
    DECLARE @newFl INT = (SELECT TOP 1 TemplateFloorID FROM TemplateFloor WHERE VenueTemplateVersionID=@newVtv);
    IF (SELECT COUNT(*) FROM TemplateSection WHERE TemplateFloorID=@newFl) <> 1
        THROW 59999, ''Phai sao chep dung 1 Section'', 1;
    DECLARE @newSec INT = (SELECT TOP 1 TemplateSectionID FROM TemplateSection WHERE TemplateFloorID=@newFl);
    IF (SELECT COUNT(*) FROM TemplateSeat WHERE TemplateSectionID=@newSec) <> 1
        THROW 59999, ''Phai sao chep dung 1 Seat'', 1;
    IF (SELECT SeatKey FROM TemplateSeat WHERE TemplateSectionID=@newSec) <> ''S1''
        THROW 59999, ''SeatKey sao chep phai giu nguyen'', 1;';
EXEC test.sp_RunTest @Suite,'CreateVenueTemplateVersion_CopyFrom_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 9. sp_DeleteVenueTemplateVersionDraft: xoa Draft rong -> SUCCESS, cascade dung
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DeleteDraft'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''S1'', N''A'', 1);
    EXEC dbo.sp_DeleteVenueTemplateVersionDraft @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    IF EXISTS (SELECT 1 FROM VenueTemplateVersion WHERE VenueTemplateVersionID=@vtv)
        THROW 59999, ''VenueTemplateVersion phai bi xoa'', 1;
    IF EXISTS (SELECT 1 FROM TemplateFloor WHERE TemplateFloorID=@fl)
        THROW 59999, ''TemplateFloor phai bi xoa theo cascade'', 1;
    IF EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSectionID=@sec)
        THROW 59999, ''TemplateSeat phai bi xoa theo cascade'', 1;';
EXEC test.sp_RunTest @Suite,'DeleteVenueTemplateVersionDraft_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- 10. sp_DeleteVenueTemplateVersionDraft: khong xoa duoc version da Published -> 60033
--     Tu dung Template/Version/Floor/Section/Seat cua chinh no roi Publish ngay
--     trong cung @SQL (xem ly do o comment truoc test 7).
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DeletePublished'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    INSERT INTO TemplateFloor (VenueTemplateVersionID, FloorKey, FloorOrder, CanvasWidth, CanvasHeight)
    VALUES (@vtv, ''ground'', 1, 1000, 800);
    SET @fl = SCOPE_IDENTITY();
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''S1'', N''A'', 1);
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_DeleteVenueTemplateVersionDraft @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;';
EXEC test.sp_RunTest @Suite,'DeleteVenueTemplateVersionDraft_PublishedRejected_Fail60033','ERROR',60033,@SQL;
