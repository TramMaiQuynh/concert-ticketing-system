-- ============================================================
-- 17_Test_StagePass_Geometry.sql
-- Kiem chung 4 ham hinh hoc StagePass (StagePass D.4) TRUOC KHI bat ky SP
-- nao dung chung: fn_TemplateGeometryIsStructurallyValid,
-- fn_TemplateGeometryToPoints, fn_TemplateGeometryIsConvex,
-- fn_TemplateGeometryOverlaps. Day la lop logic toan hoc rui ro nhat cua
-- StagePass (SAT tong quat cho da giac loi) — moi truong hop deu tinh tay
-- truoc, khong doan.
--
-- Khong dung test.sp_RunTest theo nghia "goi SP roi ROLLBACK" vi day la ham
-- thuan (khong ghi CSDL) — van dung sp_RunTest de bao cao PASS/FAIL thong
-- nhat voi cac file khac, nhung @SQL chi doc va tu THROW khi ket qua sai.
-- ============================================================
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;

DECLARE @Suite VARCHAR(255) = 'StagePass_Geometry';
DECLARE @SQL NVARCHAR(MAX);

-- ============================================================
-- fn_TemplateGeometryIsStructurallyValid
-- ============================================================
SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{"version":1,"shape":"rect","x":0,"y":0,"width":10,"height":5,"rotation":0}'') <> 1
        THROW 59999, ''Rect hop le phai tra ve 1'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_Rect_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{"version":1,"shape":"rect","x":0,"y":0,"height":5}'') <> 0
        THROW 59999, ''Rect thieu width phai tra ve 0'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_Rect_MissingWidth_Invalid','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{"version":1,"shape":"rect","x":0,"y":0,"width":0,"height":5}'') <> 0
        THROW 59999, ''Rect width=0 phai tra ve 0'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_Rect_ZeroWidth_Invalid','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{"version":1,"shape":"polygon","points":[[0,0],[10,0],[10,10]]}'') <> 1
        THROW 59999, ''Polygon tam giac hop le phai tra ve 1'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_Polygon_Triangle_OK','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{"version":1,"shape":"polygon","points":[[0,0],[10,0]]}'') <> 0
        THROW 59999, ''Polygon 2 diem phai tra ve 0'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_Polygon_TwoPoints_Invalid','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{"version":1,"shape":"polygon","points":[[0,0],[10],[10,10]]}'') <> 0
        THROW 59999, ''Polygon co diem thieu toa do y phai tra ve 0'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_Polygon_PointMissingCoord_Invalid','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{not valid json'') <> 0
        THROW 59999, ''JSON hong phai tra ve 0'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_MalformedJson_Invalid','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsStructurallyValid(N''{"version":1,"shape":"circle","x":0,"y":0,"radius":5}'') <> 0
        THROW 59999, ''Shape khong ho tro (circle) phai tra ve 0'', 1;';
EXEC test.sp_RunTest @Suite,'IsValid_UnsupportedShape_Invalid','SUCCESS',NULL,@SQL;

-- ============================================================
-- fn_TemplateGeometryToPoints — toa do tinh tay
-- ============================================================
-- rect x=0,y=0,w=100,h=50,rotation=0 -> center(50,25), 4 dinh ung voi 4 goc
-- hinh chu nhat goc: (0,0),(100,0),(100,50),(0,50) theo dung thu tu da khai
-- bao trong ham (TL,TR,BR,BL).
SET @SQL = N'
    DECLARE @P TABLE (SeqNo INT, X FLOAT, Y FLOAT);
    INSERT INTO @P SELECT * FROM dbo.fn_TemplateGeometryToPoints(N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":50,"rotation":0}'');
    IF (SELECT COUNT(*) FROM @P) <> 4 THROW 59999, ''Rect phai co dung 4 dinh'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=1 AND ABS(X-0)<0.01 AND ABS(Y-0)<0.01) THROW 59999, ''Dinh 1 phai la (0,0)'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=2 AND ABS(X-100)<0.01 AND ABS(Y-0)<0.01) THROW 59999, ''Dinh 2 phai la (100,0)'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=3 AND ABS(X-100)<0.01 AND ABS(Y-50)<0.01) THROW 59999, ''Dinh 3 phai la (100,50)'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=4 AND ABS(X-0)<0.01 AND ABS(Y-50)<0.01) THROW 59999, ''Dinh 4 phai la (0,50)'', 1;';
EXEC test.sp_RunTest @Suite,'ToPoints_Rect_NoRotation_CornersCorrect','SUCCESS',NULL,@SQL;

-- rect x=0,y=0,w=100,h=50,rotation=90 -> center(50,25), xoay 90 do quanh tam:
-- (lx,ly) -> (-ly,lx). Dinh 1 cuc bo (-50,-25) -> xoay (25,-50) -> tuyet doi (75,-25).
-- Dinh 2 cuc bo (50,-25) -> xoay (25,50) -> tuyet doi (75,75).
-- Dinh 3 cuc bo (50,25) -> xoay (-25,50) -> tuyet doi (25,75).
-- Dinh 4 cuc bo (-50,25) -> xoay (-25,-50) -> tuyet doi (25,-25).
SET @SQL = N'
    DECLARE @P TABLE (SeqNo INT, X FLOAT, Y FLOAT);
    INSERT INTO @P SELECT * FROM dbo.fn_TemplateGeometryToPoints(N''{"version":1,"shape":"rect","x":0,"y":0,"width":100,"height":50,"rotation":90}'');
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=1 AND ABS(X-75)<0.01 AND ABS(Y-(-25))<0.01) THROW 59999, ''Dinh 1 xoay 90 do sai: khong phai (75,-25)'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=2 AND ABS(X-75)<0.01 AND ABS(Y-75)<0.01) THROW 59999, ''Dinh 2 xoay 90 do sai: khong phai (75,75)'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=3 AND ABS(X-25)<0.01 AND ABS(Y-75)<0.01) THROW 59999, ''Dinh 3 xoay 90 do sai: khong phai (25,75)'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=4 AND ABS(X-25)<0.01 AND ABS(Y-(-25))<0.01) THROW 59999, ''Dinh 4 xoay 90 do sai: khong phai (25,-25)'', 1;';
EXEC test.sp_RunTest @Suite,'ToPoints_Rect_Rotation90_CornersCorrect','SUCCESS',NULL,@SQL;

SET @SQL = N'
    DECLARE @P TABLE (SeqNo INT, X FLOAT, Y FLOAT);
    INSERT INTO @P SELECT * FROM dbo.fn_TemplateGeometryToPoints(N''{"version":1,"shape":"polygon","points":[[0,0],[10,0],[10,10],[0,10]]}'');
    IF (SELECT COUNT(*) FROM @P) <> 4 THROW 59999, ''Polygon 4 diem phai tra ve dung 4 dinh'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=1 AND X=0 AND Y=0) THROW 59999, ''Thu tu diem polygon phai giu nguyen (diem 1)'', 1;
    IF NOT EXISTS (SELECT 1 FROM @P WHERE SeqNo=3 AND X=10 AND Y=10) THROW 59999, ''Thu tu diem polygon phai giu nguyen (diem 3)'', 1;';
EXEC test.sp_RunTest @Suite,'ToPoints_Polygon_PassthroughOrder_Correct','SUCCESS',NULL,@SQL;

-- ============================================================
-- fn_TemplateGeometryIsConvex — tinh tay tich co huong (xem comment file .sql)
-- ============================================================
SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsConvex(N''{"version":1,"shape":"rect","x":0,"y":0,"width":10,"height":10}'') <> 1
        THROW 59999, ''Rect luon phai loi (1)'', 1;';
EXEC test.sp_RunTest @Suite,'IsConvex_Rect_AlwaysConvex','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsConvex(N''{"version":1,"shape":"polygon","points":[[0,0],[1,0],[1,1],[0,1]]}'') <> 1
        THROW 59999, ''Hinh vuong chieu kim dong ho (CCW theo Y-len) phai loi'', 1;';
EXEC test.sp_RunTest @Suite,'IsConvex_Square_Winding1_Convex','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsConvex(N''{"version":1,"shape":"polygon","points":[[0,0],[0,1],[1,1],[1,0]]}'') <> 1
        THROW 59999, ''Hinh vuong huong nguoc lai van phai loi (SAT khong phu thuoc chieu ve)'', 1;';
EXEC test.sp_RunTest @Suite,'IsConvex_Square_Winding2_Convex','SUCCESS',NULL,@SQL;

-- Hinh chu L (loi ra) 6 dinh: (0,0)(2,0)(2,1)(1,1)(1,2)(0,2) — tinh tay xac
-- nhan doi dau tich co huong tai dinh (1,1): CD x DE = (-1,0)x(0,1) = -1,
-- trong khi 5 cap con lai deu +1 -> khong loi.
SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsConvex(N''{"version":1,"shape":"polygon","points":[[0,0],[2,0],[2,1],[1,1],[1,2],[0,2]]}'') <> 0
        THROW 59999, ''Hinh chu L (loi ra) phai KHONG loi (0)'', 1;';
EXEC test.sp_RunTest @Suite,'IsConvex_LShape_Concave','SUCCESS',NULL,@SQL;

-- 3 diem thang hang: moi tich co huong ~0 -> suy bien, coi la khong loi.
SET @SQL = N'
    IF dbo.fn_TemplateGeometryIsConvex(N''{"version":1,"shape":"polygon","points":[[0,0],[1,0],[2,0]]}'') <> 0
        THROW 59999, ''3 diem thang hang la suy bien, phai tra ve 0'', 1;';
EXEC test.sp_RunTest @Suite,'IsConvex_CollinearPoints_Degenerate','SUCCESS',NULL,@SQL;

-- ============================================================
-- fn_TemplateGeometryOverlaps — tinh tay tung truong hop
-- ============================================================
SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"rect","x":0,"y":0,"width":10,"height":10}'',
        N''{"version":1,"shape":"rect","x":20,"y":20,"width":10,"height":10}''
    ) <> 0
        THROW 59999, ''Hai rect cach xa nhau phai KHONG giao (0)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_Rects_Separated_NoOverlap','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"rect","x":0,"y":0,"width":10,"height":10}'',
        N''{"version":1,"shape":"rect","x":5,"y":5,"width":10,"height":10}''
    ) <> 1
        THROW 59999, ''Hai rect chong lan ro rang phai giao (1)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_Rects_Overlapping_Overlap','SUCCESS',NULL,@SQL;

-- Cham dung bien (canh x=10 chung) phai KHONG tinh la giao — dung quy uoc
-- "cham canh hop le" cua sp_CreateZone, xem comment file .sql.
SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"rect","x":0,"y":0,"width":10,"height":10}'',
        N''{"version":1,"shape":"rect","x":10,"y":0,"width":10,"height":10}''
    ) <> 0
        THROW 59999, ''Hai rect cham dung mot canh phai KHONG tinh la giao (0)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_Rects_TouchingEdge_NoOverlap','SUCCESS',NULL,@SQL;

-- Kim cuong (rect xoay 45 do quanh goc (0,0)): 4 dinh (0,7.071),(7.071,0),
-- (0,-7.071),(-7.071,0). AABB cua no la [-7.071,7.071]^2. Dat mot rect nho
-- NAM TRON trong AABB do (goc [6.5,6.8]x[6.5,6.8]) nhung moi diem cua no co
-- x+y>=13 > 7.071 -> nam NGOAI kim cuong that (canh tu (7.071,0) den
-- (0,7.071) la duong x+y=7.071). Day la phep thu quan trong nhat: neu ham
-- vo tinh chi so sanh AABB thay vi da giac xoay that, se BAO SAI la giao
-- nhau — dung dieu ma comment sp_CreateZone da canh bao voi hinh xoay gan
-- bien.
SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"rect","x":-5,"y":-5,"width":10,"height":10,"rotation":45}'',
        N''{"version":1,"shape":"rect","x":6.5,"y":6.5,"width":0.3,"height":0.3}''
    ) <> 0
        THROW 59999, ''Rect nho nam trong AABB cua kim cuong nhung ngoai hinh that phai KHONG giao (0) — neu FAIL o day nghia la ham dang chi so sanh AABB'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_RotatedRect_AabbFalsePositive_Avoided','SUCCESS',NULL,@SQL;

-- Doi lai: dat kim cuong that mot dinh cua no (0,7.071) nam hang trong rect
-- nho -> phai giao (1). Rect nho x=-0.5,y=6.5,w=1,h=1 -> spans [-0.5,0.5]x[6.5,7.5],
-- chua diem (0,7.071).
SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"rect","x":-5,"y":-5,"width":10,"height":10,"rotation":45}'',
        N''{"version":1,"shape":"rect","x":-0.5,"y":6.5,"width":1,"height":1}''
    ) <> 1
        THROW 59999, ''Rect nho chua dinh cua kim cuong phai giao (1)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_RotatedRect_TrueVertexHit_Detected','SUCCESS',NULL,@SQL;

-- Tam giac vs rect: tam giac (0,0)(10,0)(0,10) va rect x=1,y=1,w=2,h=2
-- (spans [1,3]x[1,3]) — diem (1,1) nam trong tam giac (x+y=2<=10, x,y>=0) -> giao.
SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"polygon","points":[[0,0],[10,0],[0,10]]}'',
        N''{"version":1,"shape":"rect","x":1,"y":1,"width":2,"height":2}''
    ) <> 1
        THROW 59999, ''Tam giac va rect chong lan phai giao (1)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_TriangleVsRect_Overlap','SUCCESS',NULL,@SQL;

-- Tam giac (0,0)(10,0)(0,10) (canh huyen x+y=10) vs rect x=20,y=20,w=5,h=5 -> khong giao.
SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"polygon","points":[[0,0],[10,0],[0,10]]}'',
        N''{"version":1,"shape":"rect","x":20,"y":20,"width":5,"height":5}''
    ) <> 0
        THROW 59999, ''Tam giac va rect cach xa phai KHONG giao (0)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_TriangleVsRect_NoOverlap','SUCCESS',NULL,@SQL;

-- Hai tam giac: A=(0,0)(10,0)(0,10) (canh huyen x+y=10); B=(5,5)(15,5)(5,15)
-- (canh huyen x+y=10 dich +10 theo x va y) — diem (5,5) la dinh chung cua ca
-- hai vung x+y<=10, nam tren bien A va la dinh cua B -> giao nhau (khong chi
-- cham bien don thuan, vung near (5,5) ca hai tam giac deu co phan dien tich
-- that chong nhau, vi du diem (4,5): tam giac A: 4+5=9<=10 hop le; tam giac B
-- can x>=5 -> (4,5) khong thuoc B. Thu diem (5,4): A: 5+4=9<=10 hop le; B can
-- y>=5 -> khong thuoc B. Can kiem tra ky hon — doi truong hop ro rang hon o
-- duoi.
SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"polygon","points":[[0,0],[10,0],[10,10],[0,10]]}'',
        N''{"version":1,"shape":"polygon","points":[[5,5],[15,5],[15,15],[5,15]]}''
    ) <> 1
        THROW 59999, ''Hai hinh vuong chong lan 1/4 dien tich phai giao (1)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_PolygonVsPolygon_Overlap','SUCCESS',NULL,@SQL;

SET @SQL = N'
    IF dbo.fn_TemplateGeometryOverlaps(
        N''{"version":1,"shape":"polygon","points":[[0,0],[10,0],[10,10],[0,10]]}'',
        N''{"version":1,"shape":"polygon","points":[[50,50],[60,50],[60,60],[50,60]]}''
    ) <> 0
        THROW 59999, ''Hai hinh vuong cach xa phai KHONG giao (0)'', 1;';
EXEC test.sp_RunTest @Suite,'Overlaps_PolygonVsPolygon_NoOverlap','SUCCESS',NULL,@SQL;
