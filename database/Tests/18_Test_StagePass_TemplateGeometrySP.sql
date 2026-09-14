-- ============================================================
-- 18_Test_StagePass_TemplateGeometrySP.sql
-- Kiem chung 4 SP dung hinh hoc StagePass (StagePass D.4):
--   sp_ConfigureTemplateFloor, sp_ConfigureTemplateObject,
--   sp_ConfigureTemplateSection, sp_ConfigureTemplateSeat.
-- Cung khuon 16_Test_StagePass_TemplateLifecycle.sql: goi qua SP, MOI test
-- tu dung du lieu cua chinh no (sp_RunTest luon ROLLBACK, xem bai hoc da
-- rut ra o file 16 va test #9 cua file 15).
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StagePass_TemplateGeometrySP';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- sp_ConfigureTemplateFloor
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG FloorOK'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    IF @fl IS NULL THROW 59999, ''TemplateFloorID phai duoc gan'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureFloor_Create_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG FloorNotAdmin'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@cust, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureFloor_NotAdmin_Fail60041','ERROR',60041,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG FloorPublished'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    INSERT INTO TemplateSection (TemplateFloorID, SectionKey, GeometryJson)
    VALUES (@fl, ''VIP'', N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'');
    SET @sec = SCOPE_IDENTITY();
    INSERT INTO TemplateSeat (TemplateSectionID, SeatID, SeatKey, RowLabel, SeatNumber)
    VALUES (@sec, @s1, ''S1'', N''A'', 1);
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    DECLARE @fl2 INT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''balcony'', @FloorOrder=2, @CanvasWidth=500, @CanvasHeight=400, @TemplateFloorID=@fl2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureFloor_VersionNotDraft_Fail60043','ERROR',60043,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl1 INT, @fl2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG FloorDupKey'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=2, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureFloor_DuplicateKey_Fail60047','ERROR',60047,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl1 INT, @fl2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG FloorDupOrder'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''balcony'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureFloor_DuplicateOrder_Fail60048','ERROR',60048,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG FloorUpdate'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorName=N''Tang tret'', @FloorOrder=1, @CanvasWidth=1200, @CanvasHeight=900, @TemplateFloorID=@fl OUTPUT;
    IF (SELECT CanvasWidth FROM TemplateFloor WHERE TemplateFloorID=@fl) <> 1200
        THROW 59999, ''CanvasWidth phai duoc cap nhat thanh 1200'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureFloor_Update_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG FloorShrink'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":900,"y":700,"width":50,"height":50,"rotation":0}'', @TemplateObjectID=@obj OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=500, @CanvasHeight=400, @TemplateFloorID=@fl OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureFloor_ShrinkBelowObject_Fail60050','ERROR',60050,@SQL;

-- ============================================================
-- sp_ConfigureTemplateObject
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG ObjOK'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}'', @TemplateObjectID=@obj OUTPUT;
    IF @obj IS NULL THROW 59999, ''TemplateObjectID phai duoc gan'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureObject_Create_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG ObjBadType'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Pool'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":10,"height":10}'', @TemplateObjectID=@obj OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureObject_InvalidType_Fail60064','ERROR',60064,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG ObjBadJson'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0}'', @TemplateObjectID=@obj OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureObject_InvalidGeometry_Fail60065','ERROR',60065,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG ObjConcave'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Wall'', @GeometryJson=N''{"version":1,"shape":"polygon","points":[[0,0],[2,0],[2,1],[1,1],[1,2],[0,2]]}'', @TemplateObjectID=@obj OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureObject_ConcavePolygon_Fail60066','ERROR',60066,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG ObjOutOfBounds'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":950,"y":20,"width":400,"height":60,"rotation":0}'', @TemplateObjectID=@obj OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureObject_OutOfCanvasBounds_Fail60067','ERROR',60067,@SQL;

-- ============================================================
-- sp_ConfigureTemplateSection
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SecOK'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":100,"y":150,"width":300,"height":200,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    IF @sec IS NULL THROW 59999, ''TemplateSectionID phai duoc gan'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureSection_Create_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SecConcave'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''LShape'', @GeometryJson=N''{"version":1,"shape":"polygon","points":[[0,0],[200,0],[200,100],[100,100],[100,200],[0,200]]}'', @TemplateSectionID=@sec OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureSection_ConcavePolygon_Fail60086','ERROR',60086,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SecOverlapStage'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}'', @TemplateObjectID=@obj OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":350,"y":40,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureSection_OverlapsStage_Fail60088','ERROR',60088,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec1 INT, @sec2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SecOverlapSibling'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''GA'', @GeometryJson=N''{"version":1,"shape":"rect","x":50,"y":50,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureSection_OverlapsSibling_Fail60089','ERROR',60089,@SQL;

-- Cap nhat CHINH Section do (khong doi hinh) khong duoc tu bao chong len
-- chinh no — kiem chung dieu khoan loai tru ban than (TemplateSectionID <>
-- ISNULL(@TemplateSectionID,-1)).
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SecUpdateSelf'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @SectionName=N''Khu VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":150,"height":150,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    IF (SELECT SectionName FROM TemplateSection WHERE TemplateSectionID=@sec) <> N''Khu VIP''
        THROW 59999, ''SectionName phai duoc cap nhat'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureSection_UpdateSelf_NoFalseOverlap_OK','SUCCESS',NULL,@SQL;

-- ============================================================
-- sp_ConfigureTemplateSeat
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SeatOK'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    IF @ts IS NULL THROW 59999, ''TemplateSeatID phai duoc gan'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureSeat_Create_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT, @ts2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SeatDupKey'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    DECLARE @s2 INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID <> @s1);
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s2, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=2, @TemplateSeatID=@ts2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureSeat_DuplicateSeatKey_Fail60108','ERROR',60108,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @s2  INT = (SELECT TOP 1 SeatID FROM Seat WHERE SeatID <> @s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts1 INT, @ts2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SeatDupGrid'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s2, @SeatKey=N''S2'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureSeat_DuplicateGridSlot_Fail60109','ERROR',60109,@SQL;

-- BAT BIEN QUAN TRONG NHAT: cung mot SeatID KHONG duoc xuat hien hai lan
-- trong CUNG mot VenueTemplateVersion, du o hai Section KHAC NHAU.
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec1 INT, @sec2 INT, @ts1 INT, @ts2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SeatDupAcrossSections'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @SectionKey=N''GA'', @GeometryJson=N''{"version":1,"shape":"rect","x":200,"y":200,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec2 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec1, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts1 OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec2, @SeatID=@s1, @SeatKey=N''S1DUP'', @RowLabel=N''B'', @SeatNumber=1, @TemplateSeatID=@ts2 OUTPUT;';
EXEC test.sp_RunTest @Suite,'ConfigureSeat_DuplicateSeatIDAcrossSections_Fail60107','ERROR',60107,@SQL;

-- Nguoc lai: CUNG mot SeatID o hai TEMPLATE (hai VenueTemplateVersion) KHAC
-- NHAU phai duoc PHEP — bat bien chi gioi han trong PHAM VI mot version,
-- dung nhu comment TemplateSeat.sql da neu (vd. 'Theatre' va 'End-stage'
-- cung Venue deu dung lai ghe khan dai co dinh).
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @vtA INT, @vtvA INT, @flA INT, @secA INT, @tsA INT;
    DECLARE @vtB INT, @vtvB INT, @flB INT, @secB INT, @tsB INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SeatSharedAcrossTemplates A'', @NewVenueTemplateID=@vtA OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vtA, @NewVenueTemplateVersionID=@vtvA OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtvA, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@flA OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@flA, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@secA OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@secA, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@tsA OUTPUT;

    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG SeatSharedAcrossTemplates B'', @NewVenueTemplateID=@vtB OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vtB, @NewVenueTemplateVersionID=@vtvB OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtvB, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@flB OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@flB, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@secB OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@secB, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@tsB OUTPUT;
    IF @tsB IS NULL THROW 59999, ''SeatID o template khac phai duoc phep, tsB phai duoc gan'', 1;';
EXEC test.sp_RunTest @Suite,'ConfigureSeat_SameSeatIDAcrossDifferentTemplates_OK','SUCCESS',NULL,@SQL;
