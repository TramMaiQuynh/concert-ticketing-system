DROP FUNCTION IF EXISTS dbo.fn_TemplateGeometryOverlaps;
GO
-- ============================================================
-- fn_TemplateGeometryOverlaps (StagePass D.4)
-- SAT (Separating Axis Theorem) TONG QUAT cho hai da giac LOI (rect la
-- truong hop dac biet, 4 dinh). Nguoi goi PHAI dam bao ca hai hinh da qua
-- fn_TemplateGeometryIsConvex = 1 truoc — xem ly do o comment ham do.
--
-- Thuat toan chuan: tap truc ung vien = phap tuyen cua MOI canh cua CA HAI
-- da giac. Chieu (dot product) tat ca dinh cua da giac A len mot truc, lay
-- [min,max]; lam tuong tu voi B. Neu ton tai MOT truc ma khoang [min,max]
-- cua A va B khong giao nhau (co "khe ho" nghiem ngat) => hai da giac KHONG
-- cham (truc do la "truc tach"). Neu khong tim duoc truc tach nao trong TAT
-- CA cac truc ung vien => hai da giac giao nhau.
--
-- QUY UOC CHAM BIEN: cham canh/dinh (khe ho = 0 CHINH XAC) duoc coi la
-- KHONG giao nhau — dung quy uoc da co trong sp_CreateZone ("cham canh van
-- hop le vi tat ca phep so sanh deu dung <" — noi do so sanh theo huong
-- NGUOC: yeu cau CA 4 truc deu cham giao nghiem ngat moi la va cham).
-- Dien dat theo "truc tach" o day: mot truc duoc coi la TACH (khong va cham)
-- khi khoang chieu A va B khong giao NGHIEM NGAT, tuc maxA <= minB (hoac
-- nguoc lai) — dung <= (khong phai <), vi <= coi CA truong hop cham bien
-- (maxA == minB) la tach duoc. Dung ban dau viet nham chieu (< voi epsilon
-- TRU), khien hai hinh cham dung bien bi bao la "giao nhau" — phat hien qua
-- suy dien tay truoc khi viet test, sua truoc khi chay lan dau.
-- Tra ve: 1 = giao nhau (chong lan THAT SU, khong tinh cham bien), 0 = khong giao nhau.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_TemplateGeometryOverlaps
(
    @GeometryJsonA NVARCHAR(MAX),
    @GeometryJsonB NVARCHAR(MAX)
)
RETURNS BIT
AS
BEGIN
    DECLARE @PA TABLE (SeqNo INT PRIMARY KEY, X FLOAT, Y FLOAT);
    DECLARE @PB TABLE (SeqNo INT PRIMARY KEY, X FLOAT, Y FLOAT);
    INSERT INTO @PA SELECT * FROM dbo.fn_TemplateGeometryToPoints(@GeometryJsonA);
    INSERT INTO @PB SELECT * FROM dbo.fn_TemplateGeometryToPoints(@GeometryJsonB);

    DECLARE @NA INT = (SELECT COUNT(*) FROM @PA);
    DECLARE @NB INT = (SELECT COUNT(*) FROM @PB);
    IF @NA < 3 OR @NB < 3
        RETURN 0; -- dau vao suy bien: coi nhu khong xac dinh duoc va cham, tu choi o tang goi (validation truoc)

    -- Truc ung vien: phap tuyen (-Ey, Ex) cua tung canh A va tung canh B.
    DECLARE @Axes TABLE (AxisID INT IDENTITY(1,1) PRIMARY KEY, Nx FLOAT, Ny FLOAT);
    INSERT INTO @Axes (Nx, Ny)
    SELECT -(p2.Y - p1.Y), (p2.X - p1.X)
    FROM @PA p1 JOIN @PA p2 ON p2.SeqNo = CASE WHEN p1.SeqNo = @NA THEN 1 ELSE p1.SeqNo + 1 END
    UNION ALL
    SELECT -(p2.Y - p1.Y), (p2.X - p1.X)
    FROM @PB p1 JOIN @PB p2 ON p2.SeqNo = CASE WHEN p1.SeqNo = @NB THEN 1 ELSE p1.SeqNo + 1 END;

    -- Loai truc suy bien (canh dai 0 — khong nen xay ra voi da giac hop le,
    -- phong thu chong chia du 0 o buoc chieu ben duoi).
    DELETE FROM @Axes WHERE Nx = 0 AND Ny = 0;

    -- Khong dung CROSS APPLY voi MIN/MAX tham chieu truc tiep cot cua truy
    -- van ngoai (ax.Nx/ax.Ny) nhan cot cua truy van trong (p.X/p.Y) trong
    -- CUNG mot bieu thuc gop — SQL Server tu choi voi loi 8124 ("Multiple
    -- columns are specified in an aggregated expression containing an outer
    -- reference"), da tai hien that khi deploy lan dau. Thay bang CROSS JOIN
    -- thuong (khong tuong quan) de vat ly hoa moi phep chieu (AxisID, nguon,
    -- gia tri) truoc, roi moi GROUP BY lay min/max — tranh han che tren.
    DECLARE @ProjRaw TABLE (AxisID INT, Src CHAR(1), Proj FLOAT);
    INSERT INTO @ProjRaw (AxisID, Src, Proj)
    SELECT ax.AxisID, 'A', p.X * ax.Nx + p.Y * ax.Ny FROM @Axes ax CROSS JOIN @PA p
    UNION ALL
    SELECT ax.AxisID, 'B', p.X * ax.Nx + p.Y * ax.Ny FROM @Axes ax CROSS JOIN @PB p;

    DECLARE @ProjAgg TABLE (AxisID INT, Src CHAR(1), MinV FLOAT, MaxV FLOAT, PRIMARY KEY (AxisID, Src));
    INSERT INTO @ProjAgg (AxisID, Src, MinV, MaxV)
    SELECT AxisID, Src, MIN(Proj), MAX(Proj)
    FROM @ProjRaw
    GROUP BY AxisID, Src;

    DECLARE @HasSeparatingAxis BIT = 0;

    IF EXISTS (
        SELECT 1
        FROM @ProjAgg a
        JOIN @ProjAgg b ON b.AxisID = a.AxisID AND a.Src = 'A' AND b.Src = 'B'
        WHERE a.MaxV <= b.MinV + 1e-6 OR b.MaxV <= a.MinV + 1e-6
    )
        SET @HasSeparatingAxis = 1;

    RETURN CASE WHEN @HasSeparatingAxis = 1 THEN 0 ELSE 1 END;
END;
GO
