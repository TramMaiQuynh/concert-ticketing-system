-- ============================================================
-- 20_Test_StagePass_TemplateCrud.sql
-- Kiem chung 5 SP CRUD bo sung sau khi soat lai toan bo tang StagePass
-- (phat hien thieu duong sua ten/archive Template va thieu duong xoa rieng
-- le Floor/Object/Section/Seat): sp_UpdateVenueTemplate,
-- sp_DeleteTemplateFloor, sp_DeleteTemplateObject, sp_DeleteTemplateSection,
-- sp_DeleteTemplateSeat. Cung khuon cac file 16/18/19: goi qua SP, moi
-- test tu dung du lieu cua chinh no.
-- ============================================================
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StagePass_TemplateCrud';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- sp_UpdateVenueTemplate
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG UpdRename'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_UpdateVenueTemplate @ActorUserID=@adm, @VenueTemplateID=@vt, @TemplateName=N''REG UpdRename V2'';
    IF (SELECT TemplateName FROM VenueTemplate WHERE VenueTemplateID=@vt) <> N''REG UpdRename V2''
        THROW 59999, ''Ten phai duoc cap nhat'', 1;';
EXEC test.sp_RunTest @Suite,'UpdateVenueTemplate_Rename_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG UpdArchive'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_UpdateVenueTemplate @ActorUserID=@adm, @VenueTemplateID=@vt, @TemplateStatus=N''Archived'';
    IF (SELECT TemplateStatus FROM VenueTemplate WHERE VenueTemplateID=@vt) <> N''Archived''
        THROW 59999, ''TemplateStatus phai la Archived'', 1;
    IF (SELECT TemplateName FROM VenueTemplate WHERE VenueTemplateID=@vt) <> N''REG UpdArchive''
        THROW 59999, ''TemplateName khong duoc doi khi chi sua status'', 1;';
EXEC test.sp_RunTest @Suite,'UpdateVenueTemplate_Archive_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG UpdNotAdmin'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_UpdateVenueTemplate @ActorUserID=@cust, @VenueTemplateID=@vt, @TemplateName=N''x'';';
EXEC test.sp_RunTest @Suite,'UpdateVenueTemplate_NotAdmin_Fail60005','ERROR',60005,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC dbo.sp_UpdateVenueTemplate @ActorUserID=@adm, @VenueTemplateID=-1, @TemplateName=N''x'';';
EXEC test.sp_RunTest @Suite,'UpdateVenueTemplate_NotExist_Fail60006','ERROR',60006,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt1 INT, @vt2 INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG UpdDupA'', @NewVenueTemplateID=@vt1 OUTPUT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG UpdDupB'', @NewVenueTemplateID=@vt2 OUTPUT;
    EXEC dbo.sp_UpdateVenueTemplate @ActorUserID=@adm, @VenueTemplateID=@vt2, @TemplateName=N''REG UpdDupA'';';
EXEC test.sp_RunTest @Suite,'UpdateVenueTemplate_DuplicateName_Fail60009','ERROR',60009,@SQL;

-- ============================================================
-- sp_DeleteTemplateFloor
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelFloor'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}'', @TemplateObjectID=@obj OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_DeleteTemplateFloor @ActorUserID=@adm, @TemplateFloorID=@fl;
    IF EXISTS (SELECT 1 FROM TemplateFloor WHERE TemplateFloorID=@fl) THROW 59999, ''Floor phai bi xoa'', 1;
    IF EXISTS (SELECT 1 FROM TemplateObject WHERE TemplateObjectID=@obj) THROW 59999, ''Object phai bi xoa theo cascade'', 1;
    IF EXISTS (SELECT 1 FROM TemplateSection WHERE TemplateSectionID=@sec) THROW 59999, ''Section phai bi xoa theo cascade'', 1;
    IF EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSeatID=@ts) THROW 59999, ''Seat phai bi xoa theo cascade'', 1;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateFloor_Cascade_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelFloorPub'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_DeleteTemplateFloor @ActorUserID=@adm, @TemplateFloorID=@fl;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateFloor_VersionNotDraft_Fail60054','ERROR',60054,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    EXEC dbo.sp_DeleteTemplateFloor @ActorUserID=@adm, @TemplateFloorID=-1;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateFloor_NotExist_Fail60053','ERROR',60053,@SQL;

SET @SQL = N'
    DECLARE @cust INT = (SELECT UserID FROM UserAccount WHERE Username=''test_cust1'');
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelFloorNotAdmin'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_DeleteTemplateFloor @ActorUserID=@cust, @TemplateFloorID=@fl;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateFloor_NotAdmin_Fail60052','ERROR',60052,@SQL;

-- ============================================================
-- sp_DeleteTemplateObject
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelObj'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}'', @TemplateObjectID=@obj OUTPUT;
    EXEC dbo.sp_DeleteTemplateObject @ActorUserID=@adm, @TemplateObjectID=@obj;
    IF EXISTS (SELECT 1 FROM TemplateObject WHERE TemplateObjectID=@obj) THROW 59999, ''Object phai bi xoa'', 1;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateObject_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @obj INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelObjPub'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateObject @ActorUserID=@adm, @TemplateFloorID=@fl, @ObjectType=N''Stage'', @GeometryJson=N''{"version":1,"shape":"rect","x":300,"y":20,"width":400,"height":60,"rotation":0}'', @TemplateObjectID=@obj OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":100,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_DeleteTemplateObject @ActorUserID=@adm, @TemplateObjectID=@obj;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateObject_VersionNotDraft_Fail60071','ERROR',60071,@SQL;

-- ============================================================
-- sp_DeleteTemplateSection
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelSec'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_DeleteTemplateSection @ActorUserID=@adm, @TemplateSectionID=@sec;
    IF EXISTS (SELECT 1 FROM TemplateSection WHERE TemplateSectionID=@sec) THROW 59999, ''Section phai bi xoa'', 1;
    IF EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSeatID=@ts) THROW 59999, ''Seat phai bi xoa theo cascade'', 1;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateSection_Cascade_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelSecPub'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_DeleteTemplateSection @ActorUserID=@adm, @TemplateSectionID=@sec;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateSection_VersionNotDraft_Fail60094','ERROR',60094,@SQL;

-- ============================================================
-- sp_DeleteTemplateSeat
-- ============================================================
SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelSeat'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_DeleteTemplateSeat @ActorUserID=@adm, @TemplateSeatID=@ts;
    IF EXISTS (SELECT 1 FROM TemplateSeat WHERE TemplateSeatID=@ts) THROW 59999, ''Seat phai bi xoa'', 1;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateSeat_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @adm INT = (SELECT UserID FROM UserAccount WHERE Username=''test_admin'');
    DECLARE @ven INT = (SELECT TOP 1 VenueID FROM Venue);
    DECLARE @s1  INT = (SELECT TOP 1 SeatID FROM Seat);
    DECLARE @zn INT = (SELECT ZoneID FROM Seat WHERE SeatID=@s1);
    DECLARE @vt INT, @vtv INT, @fl INT, @sec INT, @ts INT;
    EXEC dbo.sp_CreateVenueTemplate @ActorUserID=@adm, @VenueID=@ven, @TemplateName=N''REG DelSeatPub'', @NewVenueTemplateID=@vt OUTPUT;
    EXEC dbo.sp_CreateVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateID=@vt, @NewVenueTemplateVersionID=@vtv OUTPUT;
    EXEC dbo.sp_ConfigureTemplateFloor @ActorUserID=@adm, @VenueTemplateVersionID=@vtv, @FloorKey=N''ground'', @FloorOrder=1, @CanvasWidth=1000, @CanvasHeight=800, @TemplateFloorID=@fl OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSection @ActorUserID=@adm, @TemplateFloorID=@fl, @ZoneID=@zn, @SectionKey=N''VIP'', @GeometryJson=N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":100,"rotation":0}'', @TemplateSectionID=@sec OUTPUT;
    EXEC dbo.sp_ConfigureTemplateSeat @ActorUserID=@adm, @TemplateSectionID=@sec, @SeatID=@s1, @SeatKey=N''S1'', @RowLabel=N''A'', @SeatNumber=1, @TemplateSeatID=@ts OUTPUT;
    EXEC dbo.sp_PublishVenueTemplateVersion @ActorUserID=@adm, @VenueTemplateVersionID=@vtv;
    EXEC dbo.sp_DeleteTemplateSeat @ActorUserID=@adm, @TemplateSeatID=@ts;';
EXEC test.sp_RunTest @Suite,'DeleteTemplateSeat_VersionNotDraft_Fail60123','ERROR',60123,@SQL;
