DROP FUNCTION IF EXISTS dbo.fn_TemplateGeometryIsStructurallyValid;
GO
-- ============================================================
-- fn_TemplateGeometryIsStructurallyValid (StagePass D.4)
-- Kiem tra mot GeometryJson (quy uoc v1, xem comment TemplateSection.sql)
-- co dung cau truc de dua vao fn_TemplateGeometryToPoints/IsConvex/Overlaps
-- hay khong. CHECK constraint ISJSON() cua bang chi dam bao la JSON hop le,
-- KHONG dam bao dung "hinh dang" GeometryJson can — ham nay lap day khoang
-- do. Ham (khong phai SP) khong THROW duoc trong SQL Server, nen tra ve BIT;
-- SP goi ham nay PHAI tu THROW loi nghiep vu ro rang khi ket qua = 0, dung
-- kiem tra truoc khi goi ToPoints/IsConvex/Overlaps — cac ham do gia dinh
-- dau vao da hop le, khong tu ve thu hai.
-- Tra ve: 1 = hop le, 0 = khong hop le.
-- ============================================================
CREATE OR ALTER FUNCTION dbo.fn_TemplateGeometryIsStructurallyValid
(
    @GeometryJson NVARCHAR(MAX)
)
RETURNS BIT
AS
BEGIN
    IF @GeometryJson IS NULL OR ISJSON(@GeometryJson) <> 1
        RETURN 0;

    DECLARE @Shape VARCHAR(20) = JSON_VALUE(@GeometryJson, '$.shape');

    IF JSON_VALUE(@GeometryJson, '$.rotation') IS NOT NULL
       AND TRY_CAST(JSON_VALUE(@GeometryJson, '$.rotation') AS FLOAT) IS NULL
        RETURN 0;

    IF @Shape = 'rect'
    BEGIN
        DECLARE @X FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.x') AS FLOAT);
        DECLARE @Y FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.y') AS FLOAT);
        DECLARE @W FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.width') AS FLOAT);
        DECLARE @H FLOAT = TRY_CAST(JSON_VALUE(@GeometryJson, '$.height') AS FLOAT);

        IF @X IS NULL OR @Y IS NULL OR @W IS NULL OR @H IS NULL OR @W <= 0 OR @H <= 0
            RETURN 0;

        RETURN 1;
    END

    IF @Shape = 'polygon'
    BEGIN
        DECLARE @PointsJson NVARCHAR(MAX) = JSON_QUERY(@GeometryJson, '$.points');

        IF @PointsJson IS NULL OR ISJSON(@PointsJson) <> 1
            RETURN 0;

        IF (SELECT COUNT(*) FROM OPENJSON(@PointsJson)) < 3
            RETURN 0;

        -- Moi phan tu phai la mang dung 2 so [x,y].
        IF EXISTS (
            SELECT 1 FROM OPENJSON(@PointsJson) AS pt
            WHERE ISJSON(pt.value) <> 1
               OR (SELECT COUNT(*) FROM OPENJSON(pt.value)) <> 2
               OR TRY_CAST(JSON_VALUE(pt.value, '$[0]') AS FLOAT) IS NULL
               OR TRY_CAST(JSON_VALUE(pt.value, '$[1]') AS FLOAT) IS NULL
        )
            RETURN 0;

        RETURN 1;
    END

    RETURN 0; -- shape khong phai 'rect' hoac 'polygon'
END;
GO
