using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Domain.Models;

using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class ConcertRepository : IConcertRepository
{
    private readonly IDbConnectionFactory _factory;

    /// <summary>
    /// Điều kiện hiển thị công khai. Cả ba truy vấn public đều dùng chung hằng số này
    /// thay vì mỗi nơi tự viết một điều kiện — đó chính là cách sai lệch phát sinh:
    /// GetListAsync loại Draft, nhưng GetByIdAsync và GetSeatsAsync thì không, trong khi
    /// cả ba endpoint tương ứng đều [AllowAnonymous]. Hậu quả: chỉ cần đoán ConcertID là
    /// đọc được concert CHƯA công bố — tên, nghệ sĩ, địa điểm, cửa sổ bán, giới hạn mua,
    /// và toàn bộ sơ đồ ghế kèm giá.
    /// </summary>
    private const string PublicConcertFilter = "c.ConcertStatus <> 'Draft'";

    /// <summary>
    /// Sơ đồ ghế còn loại thêm Concert đã hủy: BR50c quy định Concert đã hủy không tham
    /// gia luồng bán vé mới (đúng với điều kiện của VW_ActiveInventoryStatus). Chi tiết
    /// Concert thì VẪN hiển thị khi đã hủy — khách cần thấy sự kiện mình đã mua bị hủy.
    /// </summary>
    private const string SellableConcertFilter = "c.ConcertStatus NOT IN ('Draft', 'Cancelled')";

    public ConcertRepository(IDbConnectionFactory factory)
    {
        _factory = factory;
    }

    public async Task<IEnumerable<ConcertListItem>> GetListAsync(int page, int pageSize, string? status)
    {
        using var conn = await _factory.OpenAsync();

        var sql = @"
            SELECT
                c.ConcertID, c.ConcertName,
                artists.ArtistName,
                v.VenueName, v.Address,
                c.StartDatetime, c.ConcertStatus, c.SalesPaused,
                c.SaleStartDatetime
            FROM Concert c
            JOIN Venue  v ON c.VenueID  = v.VenueID
            OUTER APPLY (
                SELECT STRING_AGG(CAST(a.ArtistName AS NVARCHAR(MAX)), N', ')
                       WITHIN GROUP (ORDER BY ca.ArtistOrder) AS ArtistName
                FROM ConcertArtist ca
                JOIN Artist a ON a.ArtistID = ca.ArtistID
                WHERE ca.ConcertID = c.ConcertID
            ) artists
            WHERE (@Status IS NULL OR c.ConcertStatus = @Status)
              AND " + PublicConcertFilter + @"
            ORDER BY c.StartDatetime ASC
            OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;";

        return await conn.QueryAsync<ConcertListItem>(sql, new
        {
            Status   = status,
            Offset   = (page - 1) * pageSize,
            PageSize = pageSize
        });
    }

    public async Task<ConcertDetail?> GetByIdAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();

        var sql = @"
            SELECT
                c.ConcertID, c.ConcertName,
                artists.ArtistName,
                v.VenueName, v.Address,
                c.StartDatetime, c.ConcertStatus, c.SalesPaused,
                c.SaleStartDatetime, c.SaleEndDatetime,
                c.PurchaseLimit,
                c.FairAccessEnabled, c.WaitlistEnabled
            FROM Concert c
            JOIN Venue  v ON c.VenueID  = v.VenueID
            OUTER APPLY (
                SELECT STRING_AGG(CAST(a.ArtistName AS NVARCHAR(MAX)), N', ')
                       WITHIN GROUP (ORDER BY ca.ArtistOrder) AS ArtistName
                FROM ConcertArtist ca
                JOIN Artist a ON a.ArtistID = ca.ArtistID
                WHERE ca.ConcertID = c.ConcertID
            ) artists
            WHERE c.ConcertID = @ConcertID
              AND " + PublicConcertFilter + @";";

        return await conn.QuerySingleOrDefaultAsync<ConcertDetail>(sql,
            new { ConcertID = concertId });
    }

    public async Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();

        var sql = @"
            SELECT
                es.EventSeatID AS SeatID,
                s.SeatCode     AS SeatNumber,
                z.ZoneName     AS SectionName,
                tc.TicketCategoryID,
                tc.CategoryName,
                es.InventoryStatus,
                es.SalePrice   AS Price
            FROM EventSeat es
            JOIN Concert         c  ON c.ConcertID        = es.ConcertID
            JOIN Seat            s  ON s.SeatID           = es.SeatID
            JOIN Zone            z  ON z.ZoneID           = s.ZoneID
            JOIN TicketCategory  tc ON tc.ConcertID       = es.ConcertID
                                   AND tc.TicketCategoryID = es.TicketCategoryID
            WHERE es.ConcertID = @ConcertID
              AND " + SellableConcertFilter + @"
            ORDER BY z.ZoneName, s.SeatCode;";

        return await conn.QueryAsync<SeatDto>(sql, new { ConcertID = concertId });
    }

    /// <summary>
    /// Sơ đồ chỗ ngồi công khai chỉ đọc từ revision StagePass đã khóa.
    /// </summary>
    public async Task<SeatMapDto?> GetSeatMapAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();

        var head = await conn.QuerySingleOrDefaultAsync<VenueHeadRow>(@"
            SELECT c.ConcertID, v.VenueName, v.Address,
                   (SELECT TOP 1 cmr.ConcertMapRevisionID
                    FROM   ConcertMap cm
                    JOIN   ConcertMapRevision cmr ON cmr.ConcertMapID = cm.ConcertMapID AND cmr.RevisionStatus = 'Locked'
                    WHERE  cm.ConcertID = c.ConcertID) AS LockedRevisionID
            FROM   Concert c
            JOIN   Venue v ON v.VenueID = c.VenueID
            WHERE  c.ConcertID = @ConcertID
              AND  " + SellableConcertFilter + @";",
            new { ConcertID = concertId });

        if (head is null) return null;

        // Reserved seating is published solely from the immutable StagePass
        // revision. A legacy fallback would expose inventory outside the map
        // the organizer locked for this concert.
        return head.LockedRevisionID is int revisionId
            ? await GetStagePassSeatMapAsync(concertId, head, revisionId, conn)
            : null;
    }

    /// <summary>Nhánh StagePass — đọc ConcertMapRevision đang Locked, mỗi TemplateFloor giữ canvas riêng.</summary>
    private async Task<SeatMapDto> GetStagePassSeatMapAsync(int concertId, VenueHeadRow head, int revisionId, IDbConnection conn)
    {
        var sql = @"
            SELECT f.ConcertMapRevisionFloorID, f.FloorKey, f.FloorName, f.FloorOrder, f.CanvasWidth, f.CanvasHeight
            FROM   ConcertMapRevisionFloor f
            WHERE  f.ConcertMapRevisionID = @RevisionID
            ORDER BY f.FloorOrder;

            SELECT o.ConcertMapRevisionFloorID, o.ObjectType, o.Label, o.GeometryJson
            FROM   ConcertMapRevisionObject o
            JOIN   ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = o.ConcertMapRevisionFloorID
            WHERE  f.ConcertMapRevisionID = @RevisionID;

            SELECT sec.ConcertMapRevisionSectionID, sec.ConcertMapRevisionFloorID, sec.SectionKey, sec.SectionName, sec.GeometryJson,
                   ISNULL(agg.SeatCount, 0)      AS SeatCount,
                   ISNULL(agg.AvailableCount, 0) AS AvailableCount,
                   agg.MinPrice,
                   agg.MaxPrice
            FROM   ConcertMapRevisionSection sec
            JOIN   ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = sec.ConcertMapRevisionFloorID
            OUTER  APPLY (
                    SELECT COUNT(*)      AS SeatCount,
                           SUM(CASE WHEN es.InventoryStatus = 'Available' THEN 1 ELSE 0 END) AS AvailableCount,
                           MIN(es.SalePrice) AS MinPrice,
                           MAX(es.SalePrice) AS MaxPrice
                    FROM   ConcertMapRevisionSeat cs
                    JOIN   EventSeat es ON es.EventSeatID = cs.EventSeatID
                    WHERE  cs.ConcertMapRevisionSectionID = sec.ConcertMapRevisionSectionID
            ) agg
            -- Overview la ban do cua venue, khong chi la danh sach inventory.
            -- Section chua duoc mo ban van phai hien nhu unavailable de khach
            -- khong nham no voi khoang trong hoac layout bi thieu.
            WHERE  f.ConcertMapRevisionID = @RevisionID
            ORDER BY sec.SectionName, sec.SectionKey;";

        using var grid = await conn.QueryMultipleAsync(sql, new { RevisionID = revisionId });

        var floors = (await grid.ReadAsync<CmrFloorRow>()).ToList();
        var objects = (await grid.ReadAsync<CmrObjectRow>()).ToList();
        var sections = (await grid.ReadAsync<CmrSectionSummaryRow>()).ToList();

        var sectionsByFloor = sections.ToLookup(x => x.ConcertMapRevisionFloorID);
        var objectsByFloor = objects.ToLookup(x => x.ConcertMapRevisionFloorID);

        // Tang co section van phai hien thi ke ca khi inventory cua no bang 0;
        // day la overview cua floor plan, khong phai filter "con ve".
        var floorDtos = floors
            .Where(f => sectionsByFloor[f.ConcertMapRevisionFloorID].Any())
            .Select(f => new SeatMapFloorDto(
                f.FloorKey, f.FloorName, f.CanvasWidth, f.CanvasHeight,
                objectsByFloor[f.ConcertMapRevisionFloorID].Select(o => new SeatMapObjectDto(o.ObjectType, o.Label, o.GeometryJson)).ToList(),
                sectionsByFloor[f.ConcertMapRevisionFloorID]
                    .Select(s => new SeatMapZoneDto(
                        s.ConcertMapRevisionSectionID, s.SectionKey, s.SectionName, s.GeometryJson,
                        s.SeatCount, s.AvailableCount, s.MinPrice, s.MaxPrice))
                    .ToList()))
            .ToList();

        return new SeatMapDto(concertId, head.VenueName, head.Address, floorDtos);
    }

    /// <summary>
    /// Muc hai cua so do: ghe ben trong MOT khu/section (FR11a) — CUNG MOT NGUON duy nhat
    /// voi GetSeatMapAsync: chi revision StagePass da Locked. Khong co nhanh du phong cho
    /// Zone/Seat cu, nen concert chua khoa so do se nhan null (va endpoint tra 404).
    /// Kiem tra khu/section co thuoc dia diem cua concert hay khong ngay trong truy van;
    /// thieu buoc do thi mot ID bat ky se lam lo so do cua dia diem khac, va vi endpoint
    /// nay an danh goi duoc, do la mot duong ro ri du lieu.
    /// </summary>
    public async Task<SeatMapZoneDetailDto?> GetSeatMapZoneAsync(int concertId, int zoneId)
    {
        using var conn = await _factory.OpenAsync();

        var revisionId = await conn.QuerySingleOrDefaultAsync<int?>(@"
            SELECT TOP 1 cmr.ConcertMapRevisionID
            FROM   Concert c
            JOIN   ConcertMap cm ON cm.ConcertID = c.ConcertID
            JOIN   ConcertMapRevision cmr ON cmr.ConcertMapID = cm.ConcertMapID AND cmr.RevisionStatus = 'Locked'
            WHERE  c.ConcertID = @ConcertID
              AND  " + SellableConcertFilter + @";",
            new { ConcertID = concertId });

        return revisionId is int rid
            ? await GetStagePassSectionAsync(revisionId: rid, sectionId: zoneId, conn: conn)
            : null;
    }

    private async Task<SeatMapZoneDetailDto?> GetStagePassSectionAsync(int revisionId, int sectionId, IDbConnection conn)
    {
        var sql = @"
            SELECT sec.ConcertMapRevisionSectionID, sec.SectionKey, sec.SectionName, sec.GeometryJson
            FROM   ConcertMapRevisionSection sec
            JOIN   ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = sec.ConcertMapRevisionFloorID
            WHERE  f.ConcertMapRevisionID = @RevisionID
              AND  sec.ConcertMapRevisionSectionID = @SectionID;

            SELECT es.EventSeatID AS SeatID,
                   cs.SeatKey     AS SeatNumber,
                   cs.RowLabel,
                   cs.SeatNumber  AS ColumnNumber,
                   cs.GeometryJson,
                   tc.TicketCategoryID,
                   tc.CategoryName,
                   es.InventoryStatus,
                   es.SalePrice   AS Price,
                   cs.IsAccessible,
                   cs.IsCompanion
            FROM   ConcertMapRevisionSeat cs
            JOIN   EventSeat es       ON es.EventSeatID = cs.EventSeatID
            JOIN   TicketCategory tc  ON tc.ConcertID = es.ConcertID AND tc.TicketCategoryID = es.TicketCategoryID
            WHERE  cs.ConcertMapRevisionSectionID = @SectionID
            ORDER BY cs.RowLabel, cs.SeatNumber, cs.SeatKey;";

        using var grid = await conn.QueryMultipleAsync(sql, new { RevisionID = revisionId, SectionID = sectionId });

        var section = await grid.ReadSingleOrDefaultAsync<CmrSectionRow>();
        if (section is null) return null;

        var seats = (await grid.ReadAsync<SeatMapSeatDto>()).ToList();

        return new SeatMapZoneDetailDto(section.ConcertMapRevisionSectionID, section.SectionKey, section.SectionName, section.GeometryJson, seats);
    }


    public async Task<IEnumerable<ActivePromotion>> ListActivePromotionsAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();

        // JOIN Concert để giữ đúng PublicConcertFilter: VW_ActivePromotions tự nó không biết
        // ConcertStatus, nên nếu không lọc ở đây, một concert còn Draft (chưa công bố) sẽ lộ
        // tên và giá trị khuyến mãi qua endpoint [AllowAnonymous] trước khi Organizer sẵn sàng.
        var sql = @"
            SELECT vp.PromotionID, vp.ConcertID, vp.PromotionName, vp.PromotionDescription,
                   vp.DiscountType, vp.DiscountValue, vp.StartDatetime, vp.EndDatetime,
                   vp.CodeRequiredFlag, vp.MaxApplicableQuantity, vp.MaxDiscountAmount
            FROM   VW_ActivePromotions vp
            JOIN   Concert c ON c.ConcertID = vp.ConcertID
            WHERE  vp.ConcertID = @ConcertID
              AND  " + PublicConcertFilter + @"
            ORDER BY vp.StartDatetime;";

        return await conn.QueryAsync<ActivePromotion>(sql, new { ConcertID = concertId });
    }

    // Kieu trung gian chi dung cho viec doc cac tap ket qua o tren.
    private sealed class VenueHeadRow
    {
        public int ConcertID { get; set; }
        public string VenueName { get; set; } = "";
        public string? Address { get; set; }
        public int? LockedRevisionID { get; set; }
    }

    private sealed class SeatRow
    {
        public int SeatID { get; set; }
        public string SeatNumber { get; set; } = "";
        public string? RowLabel { get; set; }
        public int? ColumnNumber { get; set; }
        public int TicketCategoryID { get; set; }
        public string CategoryName { get; set; } = "";
        public string InventoryStatus { get; set; } = "";
        public decimal Price { get; set; }
    }

    // Kieu trung gian cho GetStagePassSeatMapAsync/GetStagePassSectionAsync.
    private sealed class CmrFloorRow
    {
        public int ConcertMapRevisionFloorID { get; set; }
        public string FloorKey { get; set; } = "";
        public string? FloorName { get; set; }
        public int FloorOrder { get; set; }
        public int CanvasWidth { get; set; }
        public int CanvasHeight { get; set; }
    }

    private sealed class CmrObjectRow
    {
        public int ConcertMapRevisionFloorID { get; set; }
        public string ObjectType { get; set; } = "";
        public string? Label { get; set; }
        public string GeometryJson { get; set; } = "";
    }

    private sealed class CmrSectionSummaryRow
    {
        public int ConcertMapRevisionSectionID { get; set; }
        public int ConcertMapRevisionFloorID { get; set; }
        public string SectionKey { get; set; } = "";
        public string? SectionName { get; set; }
        public string GeometryJson { get; set; } = "";
        public int SeatCount { get; set; }
        public int AvailableCount { get; set; }
        public decimal? MinPrice { get; set; }
        public decimal? MaxPrice { get; set; }
    }

    private sealed class CmrSectionRow
    {
        public int ConcertMapRevisionSectionID { get; set; }
        public string SectionKey { get; set; } = "";
        public string? SectionName { get; set; }
        public string GeometryJson { get; set; } = "";
    }
}
