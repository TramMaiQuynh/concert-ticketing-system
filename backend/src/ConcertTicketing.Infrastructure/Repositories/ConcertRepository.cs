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
                a.ArtistName,
                v.VenueName, v.Address,
                c.StartDatetime, c.ConcertStatus, c.SalesPaused,
                c.SaleStartDatetime
            FROM Concert c
            JOIN Artist a ON c.ArtistID = a.ArtistID
            JOIN Venue  v ON c.VenueID  = v.VenueID
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
                a.ArtistName,
                v.VenueName, v.Address,
                c.StartDatetime, c.ConcertStatus, c.SalesPaused,
                c.SaleStartDatetime, c.SaleEndDatetime,
                c.PurchaseLimit,
                c.FairAccessEnabled, c.WaitlistEnabled
            FROM Concert c
            JOIN Artist a ON c.ArtistID = a.ArtistID
            JOIN Venue  v ON c.VenueID  = v.VenueID
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
                s.SeatLabel    AS [Row],
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
    /// Sơ đồ chỗ ngồi (FR11a).
    ///
    /// Dùng QueryMultiple để lấy cả ba tầng trong MỘT vòng gọi database: hình học
    /// địa điểm, danh sách khu, và ghế kèm trạng thái kho vé. Gọi ba lần riêng sẽ
    /// mở ra khoảng thời gian giữa các lần đọc, và sơ đồ có thể mô tả một trạng
    /// thái chưa từng tồn tại — ví dụ khu đã bị đổi vị trí giữa hai lần đọc.
    ///
    /// Khu VÉ ĐỨNG được lấy dù không có ghế nào: nó bán theo sức chứa, và bỏ nó
    /// khỏi sơ đồ nghĩa là khách không thấy một phần khán phòng có thật.
    /// </summary>
    public async Task<SeatMapDto?> GetSeatMapAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();

        var sql = @"
            SELECT c.ConcertID, v.VenueName, v.Address,
                   v.MapWidth, v.MapHeight, v.StageX, v.StageY, v.StageWidth, v.StageHeight
            FROM   Concert c
            JOIN   Venue v ON v.VenueID = c.VenueID
            WHERE  c.ConcertID = @ConcertID
              AND  " + SellableConcertFilter + @";

            SELECT z.ZoneID, z.ZoneCode, z.ZoneName, z.ZoneType, z.ZoneLevel,
                   z.ZoneX, z.ZoneY, z.ZoneWidth, z.ZoneHeight, z.ZoneRotation, z.ZoneCapacity,
                   -- Tong hop ngay trong SQL. Keo ca ghe ve roi dem o C# se lam mat
                   -- toan bo cai loi cua viec chia hai muc.
                   ISNULL(agg.SeatCount, 0)      AS SeatCount,
                   ISNULL(agg.AvailableCount, 0) AS AvailableCount,
                   agg.MinPrice,
                   agg.MaxPrice
            FROM   Zone z
            JOIN   Concert c ON c.VenueID = z.VenueID
            OUTER  APPLY (
                    SELECT COUNT(*)      AS SeatCount,
                           SUM(CASE WHEN es.InventoryStatus = 'Available' THEN 1 ELSE 0 END) AS AvailableCount,
                           MIN(es.SalePrice) AS MinPrice,
                           MAX(es.SalePrice) AS MaxPrice
                    FROM   EventSeat es
                    JOIN   Seat s ON s.SeatID = es.SeatID
                    WHERE  es.ConcertID = @ConcertID AND s.ZoneID = z.ZoneID
            ) agg
            WHERE  c.ConcertID = @ConcertID
              AND  z.ZoneStatus = 'Active'
              AND (z.ZoneType = 'GeneralAdmission' OR agg.SeatCount > 0)
            ORDER BY z.ZoneLevel, z.ZoneY, z.ZoneX, z.ZoneCode;";

        using var grid = await conn.QueryMultipleAsync(sql, new { ConcertID = concertId });

        var venue = await grid.ReadSingleOrDefaultAsync<VenueMapRow>();
        if (venue is null) return null;

        var zones = (await grid.ReadAsync<ZoneRow>()).ToList();

        return new SeatMapDto(
            venue.ConcertID, venue.VenueName, venue.Address,
            venue.MapWidth, venue.MapHeight,
            venue.StageX, venue.StageY, venue.StageWidth, venue.StageHeight,
            zones.Select(z => new SeatMapZoneDto(
                z.ZoneID, z.ZoneCode, z.ZoneName, z.ZoneType, z.ZoneLevel,
                z.ZoneX, z.ZoneY, z.ZoneWidth, z.ZoneHeight, z.ZoneRotation, z.ZoneCapacity,
                z.SeatCount, z.AvailableCount, z.MinPrice, z.MaxPrice))
                 .ToList());
    }

    /// <summary>
    /// Muc hai cua so do: ghe ben trong MOT khu (FR11a).
    ///
    /// Kiem tra khu co thuoc dia diem cua concert hay khong ngay trong truy van.
    /// Thieu buoc do thi mot ZoneID bat ky se lam lo so do cua dia diem khac —
    /// va vi endpoint nay an danh goi duoc, do la mot duong ro ri du lieu.
    /// </summary>
    public async Task<SeatMapZoneDetailDto?> GetSeatMapZoneAsync(int concertId, int zoneId)
    {
        using var conn = await _factory.OpenAsync();

        var sql = @"
            SELECT z.ZoneID, z.ZoneCode, z.ZoneName, z.ZoneType, z.ZoneLevel,
                   z.ZoneX, z.ZoneY, z.ZoneWidth, z.ZoneHeight, z.ZoneRotation, z.ZoneCapacity
            FROM   Zone z
            JOIN   Concert c ON c.VenueID = z.VenueID
            WHERE  c.ConcertID = @ConcertID
              AND  z.ZoneID    = @ZoneID
              AND  z.ZoneStatus = 'Active'
              AND  " + SellableConcertFilter + @";

            SELECT es.EventSeatID     AS SeatID,
                   s.SeatCode         AS SeatNumber,
                   s.SeatRowLabel     AS RowLabel,
                   s.SeatColumnNumber AS ColumnNumber,
                   s.ZoneID,
                   tc.TicketCategoryID,
                   tc.CategoryName,
                   es.InventoryStatus,
                   es.SalePrice       AS Price
            FROM   EventSeat es
            JOIN   Seat s            ON s.SeatID = es.SeatID
            JOIN   TicketCategory tc ON tc.ConcertID = es.ConcertID
                                    AND tc.TicketCategoryID = es.TicketCategoryID
            WHERE  es.ConcertID = @ConcertID
              AND  s.ZoneID     = @ZoneID
            ORDER BY s.SeatRowLabel, s.SeatColumnNumber, s.SeatCode;";

        using var grid = await conn.QueryMultipleAsync(sql, new { ConcertID = concertId, ZoneID = zoneId });

        var zone = await grid.ReadSingleOrDefaultAsync<ZoneRow>();
        if (zone is null) return null;

        var seats = (await grid.ReadAsync<SeatRow>()).ToList();

        return new SeatMapZoneDetailDto(
            zone.ZoneID, zone.ZoneCode, zone.ZoneName, zone.ZoneType, zone.ZoneLevel,
            zone.ZoneX, zone.ZoneY, zone.ZoneWidth, zone.ZoneHeight, zone.ZoneRotation, zone.ZoneCapacity,
            seats.Select(x => new SeatMapSeatDto(
                x.SeatID, x.SeatNumber, x.RowLabel, x.ColumnNumber,
                x.TicketCategoryID, x.CategoryName, x.InventoryStatus, x.Price)).ToList());
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

    // Kiểu trung gian chỉ dùng cho việc đọc ba tập kết quả ở trên.
    private sealed class VenueMapRow
    {
        public int ConcertID { get; set; }
        public string VenueName { get; set; } = "";
        public string? Address { get; set; }
        public int? MapWidth { get; set; }
        public int? MapHeight { get; set; }
        public int? StageX { get; set; }
        public int? StageY { get; set; }
        public int? StageWidth { get; set; }
        public int? StageHeight { get; set; }
    }

    private sealed class ZoneRow
    {
        public int ZoneID { get; set; }
        public string ZoneCode { get; set; } = "";
        public string? ZoneName { get; set; }
        public string ZoneType { get; set; } = "Seated";
        public int? ZoneLevel { get; set; }
        public int? ZoneX { get; set; }
        public int? ZoneY { get; set; }
        public int? ZoneWidth { get; set; }
        public int? ZoneHeight { get; set; }
        public decimal? ZoneRotation { get; set; }
        public int? ZoneCapacity { get; set; }
        public int SeatCount { get; set; }
        public int AvailableCount { get; set; }
        public decimal? MinPrice { get; set; }
        public decimal? MaxPrice { get; set; }
    }

    private sealed class SeatRow
    {
        public int SeatID { get; set; }
        public string SeatNumber { get; set; } = "";
        public string? RowLabel { get; set; }
        public int? ColumnNumber { get; set; }
        public int ZoneID { get; set; }
        public int TicketCategoryID { get; set; }
        public string CategoryName { get; set; } = "";
        public string InventoryStatus { get; set; } = "";
        public decimal Price { get; set; }
    }
}
