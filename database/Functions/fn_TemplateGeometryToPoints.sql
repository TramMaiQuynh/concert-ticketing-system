DROP FUNCTION IF EXISTS dbo.fn_TemplateGeometryToPoints;
GO
-- ============================================================
-- fn_TemplateGeometryToPoints (StagePass D.4)
-- Quy GeometryJson (rect hoac polygon, quy uoc v1) ve mot danh sach dinh
-- (SeqNo, X, Y) THEO CHU VI — dau vao cho fn_TemplateGeometryIsConvex va
-- fn_TemplateGeometryOverlaps. Gia dinh dau vao DA hop le cau truc (goi
-- fn_TemplateGeometryIsStructurallyValid truoc, xem comment o do) — ham nay
-- khong tu ve them lan hai, vi ham SQL Server khong THROW duoc.
--
-- rect -> 4 dinh: quy ve tam + nua-rong/cao roi xoay quanh tam bang ma tran
-- xoay chuan (rx = lx*cos - ly*sin, ry = lx*sin + ly*cos) — CHINH LA cong
-- thuc da dung de tinh bao xoay trong sp_CreateZone (extent = |hw*cos| +
-- |hh*sin|), chi khac o day tra ve DINH THAT thay vi hop bao AABB.
-- polygon -> giu nguyen thu tu points[] trong JSON.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_TemplateGeometryToPoints
(
    @GeometryJson NVARCHAR(MAX)
)
RETURNS @Points TABLE (SeqNo INT PRIMARY KEY, X FLOAT NOT NULL, Y FLOAT NOT NULL)
AS
BEGIN
    DECLARE @Shape VARCHAR(20) = JSON_VALUE(@GeometryJson, '$.shape');

    IF @Shape = 'rect'
    BEGIN
        DECLARE @X FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.x') AS FLOAT);
        DECLARE @Y FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.y') AS FLOAT);
        DECLARE @W FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.width') AS FLOAT);
        DECLARE @H FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.height') AS FLOAT);
        DECLARE @RotDeg FLOAT = ISNULL(TRY_CAST(JSON_VALUE(@GeometryJson, '$.rotation') AS FLOAT), 0);
        DECLARE @Rad FLOAT = @RotDeg * PI() / 180.0;
        DECLARE @Cos FLOAT = COS(@Rad), @Sin FLOAT = SIN(@Rad);
        DECLARE @CenterX FLOAT = @X + @W / 2.0, @CenterY FLOAT = @Y + @H / 2.0;
        DECLARE @HalfW FLOAT = @W / 2.0, @HalfH FLOAT = @H / 2.0;

        -- 4 dinh cuc bo (chua xoay), thu tu theo chieu kim dong ho tu goc tren-trai.
        DECLARE @Local TABLE (SeqNo INT, LX FLOAT, LY FLOAT);
        INSERT INTO @Local (SeqNo, LX, LY) VALUES
            (1, -@HalfW, -@HalfH),
            (2,  @HalfW, -@HalfH),
            (3,  @HalfW,  @HalfH),
            (4, -@HalfW,  @HalfH);

        INSERT INTO @Points (SeqNo, X, Y)
        SELECT SeqNo,
               @CenterX + (LX * @Cos - LY * @Sin),
               @CenterY + (LX * @Sin + LY * @Cos)
        FROM @Local;

        RETURN;
    END

    IF @Shape = 'polygon'
    BEGIN
        INSERT INTO @Points (SeqNo, X, Y)
        SELECT CAST(pt.[key] AS INT) + 1,
               TRY_CAST(JSON_VALUE(pt.value, '$[0]') AS FLOAT),
               TRY_CAST(JSON_VALUE(pt.value, '$[1]') AS FLOAT)
        FROM OPENJSON(JSON_QUERY(@GeometryJson, '$.points')) AS pt;

        RETURN;
    END

    -- Shape khong nhan dien duoc: tra ve tap rong (input le ra da bi chan o
    -- fn_TemplateGeometryIsStructurallyValid truoc khi toi day).
    RETURN;
END;
GO
