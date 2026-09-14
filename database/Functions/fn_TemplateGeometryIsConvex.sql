DROP FUNCTION IF EXISTS dbo.fn_TemplateGeometryIsConvex;
GO
-- ============================================================
-- fn_TemplateGeometryIsConvex (StagePass D.4)
-- SAT (Separating Axis Theorem) chi dung duoc CHINH XAC cho da giac LOI —
-- voi da giac lom, SAT co the bao "khong cham" trong khi thuc te co cham
-- (false negative), vi mot truc phap tuyen co the "vo tinh" tach duoc hai
-- hinh du chung thuc su giao nhau o phan loi ra cua hinh loi kia. Vi vay
-- fn_TemplateGeometryOverlaps CHI duoc goi sau khi ham nay xac nhan LOI cho
-- ca hai hinh — day la gioi han duoc ghi nhan CO CHU DICH cua D.1/D.4, khong
-- phai thieu sot: sp_ConfigureTemplateSection se THROW loi ro rang khi
-- Section duoc ve dang loi ("hinh khong loi, khong ho tro va cham chinh xac"),
-- khong am tham chap nhan mot da giac loi co the gay sai lech va cham sau nay.
--
-- Thuat toan: voi da giac 'rect' luon loi theo cau truc (tra ve 1 ngay).
-- Voi 'polygon': tinh tich co huong (cross product) cua tung cap canh lien
-- tiep quanh chu vi; da giac don (khong tu cat) la loi khi VA CHI KHI tat ca
-- tich co huong khac-khong cung dau (chieu kim dong ho hoac nguoc kim dong ho
-- deu duoc — dau nao cung chap nhan mien la NHAT QUAN). Diem gan thang hang
-- (tich co huong ~0) duoc coi la trung tinh, khong pha vo tinh loi. Neu tat
-- ca tich co huong deu ~0 (moi diem thang hang, da giac suy bien thanh doan
-- thang), coi la KHONG loi (khong phai mot vung 2 chieu that).
-- Tra ve: 1 = loi (hoac rect), 0 = khong loi/suy bien.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_TemplateGeometryIsConvex
(
    @GeometryJson NVARCHAR(MAX)
)
RETURNS BIT
AS
BEGIN
    IF JSON_VALUE(@GeometryJson, '$.shape') = 'rect'
        RETURN 1;

    DECLARE @P TABLE (SeqNo INT PRIMARY KEY, X FLOAT, Y FLOAT);
    INSERT INTO @P SELECT * FROM dbo.fn_TemplateGeometryToPoints(@GeometryJson);

    DECLARE @N INT = (SELECT COUNT(*) FROM @P);
    IF @N < 3
        RETURN 0;

    -- Canh i: tu dinh i den dinh (i+1), vong lai dinh 1 sau dinh cuoi.
    DECLARE @Edges TABLE (SeqNo INT PRIMARY KEY, Ex FLOAT, Ey FLOAT);
    INSERT INTO @Edges (SeqNo, Ex, Ey)
    SELECT p1.SeqNo, p2.X - p1.X, p2.Y - p1.Y
    FROM @P p1
    JOIN @P p2 ON p2.SeqNo = CASE WHEN p1.SeqNo = @N THEN 1 ELSE p1.SeqNo + 1 END;

    -- Tich co huong cua canh i voi canh (i+1) — do doi huong tai dinh noi hai canh.
    DECLARE @PosCount INT, @NegCount INT;
    SELECT
        @PosCount = SUM(CASE WHEN e1.Ex * e2.Ey - e1.Ey * e2.Ex > 1e-9 THEN 1 ELSE 0 END),
        @NegCount = SUM(CASE WHEN e1.Ex * e2.Ey - e1.Ey * e2.Ex < -1e-9 THEN 1 ELSE 0 END)
    FROM @Edges e1
    JOIN @Edges e2 ON e2.SeqNo = CASE WHEN e1.SeqNo = @N THEN 1 ELSE e1.SeqNo + 1 END;

    RETURN CASE WHEN (@PosCount > 0 AND @NegCount = 0) OR (@NegCount > 0 AND @PosCount = 0) THEN 1 ELSE 0 END;
END;
GO
