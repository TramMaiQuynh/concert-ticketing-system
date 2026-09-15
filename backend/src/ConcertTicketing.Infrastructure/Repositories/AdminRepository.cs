using System.Data;
using System.Text.Json;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public partial class AdminRepository : IAdminRepository
{
    private readonly IDbConnectionFactory _factory;

    public AdminRepository(IDbConnectionFactory factory)
    {
        _factory = factory;
    }

    /// <summary>
    /// Danh mục địa điểm cho organizer chọn (FR11a).
    ///
    /// Đếm khu và ghế bằng subquery tương quan thay vì JOIN + GROUP BY: một địa
    /// điểm có thể có hàng nghìn ghế, và JOIN rồi gom lại sẽ kéo toàn bộ số dòng
    /// đó qua mạng chỉ để lấy ra một con số.
    ///
    /// Mặc định ẨN địa điểm Inactive: organizer không được chọn một địa điểm đã
    /// ngừng sử dụng cho concert mới. `includeInactive` dành cho màn quản trị.
    /// </summary>
    public async Task<IEnumerable<VenueListItem>> ListVenuesAsync(bool includeInactive)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<VenueListItem>(@"
            SELECT v.VenueID, v.VenueName, v.Address, v.VenueStatus,
                   CAST(CASE WHEN v.MapWidth IS NOT NULL AND v.MapHeight IS NOT NULL
                             THEN 1 ELSE 0 END AS BIT) AS HasSeatMap,
                   (SELECT COUNT(*) FROM Zone z
                     WHERE z.VenueID = v.VenueID AND z.ZoneStatus = 'Active')  AS ZoneCount,
                   (SELECT COUNT(*) FROM Seat s
                     WHERE s.VenueID = v.VenueID AND s.SeatStatus = 'Active')  AS SeatCount,
                   v.MapWidth, v.MapHeight,
                   v.StageX, v.StageY, v.StageWidth, v.StageHeight
            FROM   Venue v
            WHERE  (@IncludeInactive = 1 OR v.VenueStatus = 'Active')
            ORDER BY v.VenueName;",
            new { IncludeInactive = includeInactive });
    }

    /// <summary>Các khu của một địa điểm — để organizer xem trước bố cục.</summary>
    public async Task<IEnumerable<VenueZoneListItem>> ListVenueZonesAsync(int venueId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<VenueZoneListItem>(@"
            SELECT z.ZoneID, z.ZoneCode, z.ZoneName, z.ZoneType, z.ZoneStatus,
                   z.ZoneLevel, z.ZoneCapacity,
                   (SELECT COUNT(*) FROM Seat s
                     WHERE s.ZoneID = z.ZoneID AND s.SeatStatus = 'Active') AS SeatCount,
                   z.ZoneX, z.ZoneY, z.ZoneWidth, z.ZoneHeight, z.ZoneRotation
            FROM   Zone z
            WHERE  z.VenueID = @VenueID
            ORDER BY z.ZoneLevel, z.ZoneCode;",
            new { VenueID = venueId });
    }

    /// <summary>
    /// Tóm tắt doanh thu/tồn kho một Concert (FR55) — đọc VW_ConcertSalesSummary.
    /// View tự lọc theo SESSION_CONTEXT(N'UserID') (RLS: Organizer chỉ thấy Concert
    /// của mình, Admin thấy toàn bộ), nên KHÔNG cần thêm điều kiện sở hữu ở đây.
    /// 0 dòng = không sở hữu HOẶC ConcertID không tồn tại — controller quy về 404.
    /// </summary>
    public async Task<ConcertSalesSummaryDto?> GetConcertSalesSummaryAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QuerySingleOrDefaultAsync<ConcertSalesSummaryDto>(@"
            SELECT ConcertID, ConcertName, ArtistName, VenueName, ConcertStatus, StartDatetime,
                   TotalInventorySeats, AvailableSeats, BookedSeats, OnHoldSeats,
                   TotalRevenue, ConfirmedBookings, CancelledBookings, ExpiredBookings
            FROM   VW_ConcertSalesSummary
            WHERE  ConcertID = @ConcertID;",
            new { ConcertID = concertId });
    }

    /// <summary>Tỷ lệ check-in một Concert (FR56) — đọc VW_CheckInReport, cùng RLS.</summary>
    public async Task<ConcertCheckInReportDto?> GetConcertCheckInReportAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QuerySingleOrDefaultAsync<ConcertCheckInReportDto>(@"
            SELECT ConcertID, ConcertName, StartDatetime,
                   TotalIssuedTickets, TotalCheckedIn, PendingEntry, CheckInRatePct
            FROM   VW_CheckInReport
            WHERE  ConcertID = @ConcertID;",
            new { ConcertID = concertId });
    }

    /// <summary>
    /// Danh sách người giữ từng vé của một Concert (BP14) — đọc VW_ConcertAttendeeList,
    /// cùng RLS. Mảng rỗng là kết quả hợp lệ (Concert chưa phát hành vé nào), không
    /// phải lỗi — khác GetConcertSalesSummaryAsync/GetConcertCheckInReportAsync vốn
    /// luôn có đúng 1 dòng cho mọi Concert tồn tại.
    /// </summary>
    public async Task<IEnumerable<AttendeeListItem>> ListConcertAttendeesAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AttendeeListItem>(@"
            SELECT TicketID, BookingID, ConcertID, TicketStatus, IssuedTimestamp, UsedTimestamp, CancelledTimestamp,
                   SeatCode, ZoneName, CategoryName, CustomerUserID, Username, DisplayName
            FROM   VW_ConcertAttendeeList
            WHERE  ConcertID = @ConcertID
            ORDER  BY ZoneName, SeatCode;",
            new { ConcertID = concertId });
    }

    /// <summary>
    /// Danh sách chờ của một Concert (BO11–BO12). Như ba báo cáo ở trên, không truyền
    /// ActorUserID: VW_WaitlistQueue tự lọc theo Concert.OrganizerUserID hoặc Role Admin
    /// bằng SESSION_CONTEXT. Organizer không sở hữu Concert này nhận mảng rỗng, không lỗi —
    /// cùng lý do với ListConcertAttendeesAsync.
    /// </summary>
    public async Task<IEnumerable<WaitlistQueueItem>> ListConcertWaitlistAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<WaitlistQueueItem>(@"
            SELECT WaitlistID, ConcertID, ConcertName, WaitlistStatus, AllocationPolicy,
                   WaitlistEntryID, CustomerUserID, Username, DisplayName,
                   JoinedTimestamp, QueuePosition, EntryStatus,
                   TicketCategoryID, CategoryName, RequestedQuantity, ActiveAllocationCount,
                   OpportunityGrantedTimestamp, OpportunityExpiryTimestamp, ResultingBookingID
            FROM   VW_WaitlistQueue
            WHERE  ConcertID = @ConcertID
            ORDER  BY QueuePosition;",
            new { ConcertID = concertId });
    }

    /// <summary>
    /// Tra cứu nhật ký kiểm toán (FR59/FR59a).
    ///
    /// Không truyền ActorUserID để lọc quyền: VW_AuditTrail chỉ trả dữ liệu khi người
    /// đang đăng nhập giữ Role Admin đang hoạt động — phiên khác nhận 0 dòng (fail-closed).
    /// Endpoint gọi vào đây vẫn phải [Authorize(Roles = "Admin")]: hai lớp độc lập.
    ///
    /// DbType.AnsiString cho EntityType/EntityID: hai cột này là VARCHAR(64) và là hai cột
    /// dẫn đầu của IX_AuditRecord_Entity. Tham số NVARCHAR sẽ buộc SQL Server ép kiểu CỘT
    /// và vô hiệu hoá index seek trên chính bảng lớn nhất hệ thống.
    /// </summary>
    public async Task<IEnumerable<AuditRecordItem>> QueryAuditTrailAsync(AuditQueryRequest r)
    {
        // Trần cứng phía máy chủ: người gọi không được phép yêu cầu số dòng tuỳ ý.
        const int DefaultLimit = 100;
        const int MaxLimit     = 500;
        var limit = Math.Clamp(r.Limit ?? DefaultLimit, 1, MaxLimit);

        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@Limit", limit, DbType.Int32);
        p.Add("@EntityType", string.IsNullOrWhiteSpace(r.EntityType) ? null : r.EntityType,
              DbType.AnsiString, size: 64);
        p.Add("@EntityID", string.IsNullOrWhiteSpace(r.EntityId) ? null : r.EntityId,
              DbType.AnsiString, size: 64);
        p.Add("@ActorUserID", r.ActorUserId, DbType.Int32);
        p.Add("@From", r.From, DbType.DateTime2);
        p.Add("@To", r.To, DbType.DateTime2);

        return await conn.QueryAsync<AuditRecordItem>(@"
            SELECT TOP (@Limit)
                   AuditID, EventTimestamp, EventType, Action, EntityType, EntityID,
                   ActorUserID, ActorUsername, PreviousValue, NewValue, TransactionReference
            FROM   VW_AuditTrail
            WHERE  (@EntityType  IS NULL OR EntityType  = @EntityType)
              AND  (@EntityID    IS NULL OR EntityID    = @EntityID)
              AND  (@ActorUserID IS NULL OR ActorUserID = @ActorUserID)
              AND  (@From        IS NULL OR EventTimestamp >= @From)
              AND  (@To          IS NULL OR EventTimestamp <  @To)
            -- AuditID phá hoà: hai bản ghi cùng một mốc thời gian vẫn phải có thứ tự
            -- xác định, nếu không phân trang/đối soát sẽ cho kết quả khác nhau mỗi lần.
            ORDER  BY EventTimestamp DESC, AuditID DESC
            -- Mẫu `(@p IS NULL OR cot = @p)` buộc SQL Server dựng MỘT kế hoạch dùng chung
            -- cho mọi tổ hợp tham số, nên nó không dám seek trên IX_AuditRecord_Entity —
            -- đã đo trên 40.000 bản ghi: tra cứu lịch sử của MỘT entity tốn 418 logical
            -- reads (quét bảng). Với RECOMPILE, kế hoạch được dựng theo đúng giá trị tham
            -- số của lần gọi này: còn 11 reads — giảm 38 lần.
            --
            -- LƯU Ý: đây là quyết định NGƯỢC với TRG_StateTransition (nơi RECOMPILE đã bị
            -- loại bỏ để chọn HASH JOIN hint), và ngược có căn cứ chứ không mâu thuẫn:
            -- trigger chạy ở MỌI lần cập nhật một dòng nên chi phí biên dịch lấn át tất cả
            -- (đo được chậm 17 lần); còn đây là tra cứu thủ công của Admin, tần suất rất
            -- thấp, và độ chọn lọc chênh nhau hàng nghìn lần giữa các tổ hợp tham số —
            -- đúng trường hợp mà RECOMPILE sinh ra để giải quyết.
            OPTION (RECOMPILE);", p);
    }

    public async Task<IEnumerable<ArtistListItem>> ListArtistsAsync(bool includeRetired)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<ArtistListItem>(@"
            SELECT a.ArtistID, a.ArtistName, a.ArtistDescription, a.ArtistStatus
            FROM   Artist a
            WHERE  (@IncludeRetired = 1 OR a.ArtistStatus = 'Active')
            ORDER BY a.ArtistName;",
            new { IncludeRetired = includeRetired });
    }

    public async Task<int> CreateConcertAsync(int actorUserId, CreateConcertRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@OrganizerUserID", actorUserId, DbType.Int32);
        p.Add("@ArtistIDs", JsonSerializer.Serialize(r.ArtistIds), DbType.String);
        p.Add("@VenueID", r.VenueId, DbType.Int32);
        p.Add("@ConcertName", r.ConcertName, DbType.String, size: 255);
        p.Add("@StartDatetime", r.StartDatetime, DbType.DateTime2);
        p.Add("@EndDatetime", r.EndDatetime, DbType.DateTime2);
        // Không truyền @ConcertStatus: sp_CreateConcert luôn tạo Concert ở trạng thái Draft
        // và mọi chuyển trạng thái phải đi qua sp_UpdateConcertStatus (BR49).
        p.Add("@PurchaseLimit", r.PurchaseLimit, DbType.Int32);
        p.Add("@SaleStartDatetime", r.SaleStartDatetime, DbType.DateTime2);
        p.Add("@SaleEndDatetime", r.SaleEndDatetime, DbType.DateTime2);
        p.Add("@TemporaryHoldDuration", r.TemporaryHoldDuration, DbType.Int32);
        p.Add("@FairAccessEnabled", r.FairAccessEnabled, DbType.Boolean);
        p.Add("@WaitlistEnabled", r.WaitlistEnabled, DbType.Boolean);
        p.Add("@SalesPaused", r.SalesPaused, DbType.Boolean);
        p.Add("@CancellationPolicy", r.CancellationPolicy, DbType.String, size: 500);
        p.Add("@RefundPolicy", r.RefundPolicy, DbType.String, size: 500);
        // Dạng có cấu trúc của chính sách hủy/hoàn (BR31a, BR32a) — NULL thì SP dùng DEFAULT.
        p.Add("@CancellationDeadlineHours", r.CancellationDeadlineHours, DbType.Int32);
        p.Add("@RefundPercentage", r.RefundPercentage, DbType.Decimal);
        // Người THỰC HIỆN, tách khỏi @OrganizerUserID là người SỞ HỮU. Hiện tại API chỉ
        // cho Organizer tự tạo Concert của mình nên hai giá trị trùng nhau, nhưng truyền
        // tường minh để SP kiểm được quyền thay vì suy đoán (58008).
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@NewConcertID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateConcert", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewConcertID");
    }

    public async Task UpdateConcertAsync(int concertId, int actorUserId, UpdateConcertRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertName", r.ConcertName, DbType.String, size: 255);
        p.Add("@ArtistIDs", r.ArtistIds is null ? null : JsonSerializer.Serialize(r.ArtistIds), DbType.String);
        p.Add("@VenueID", r.VenueId, DbType.Int32);
        p.Add("@StartDatetime", r.StartDatetime, DbType.DateTime2);
        p.Add("@EndDatetime", r.EndDatetime, DbType.DateTime2);
        p.Add("@SaleStartDatetime", r.SaleStartDatetime, DbType.DateTime2);
        p.Add("@SaleEndDatetime", r.SaleEndDatetime, DbType.DateTime2);
        p.Add("@PurchaseLimit", r.PurchaseLimit, DbType.Int32);
        p.Add("@TemporaryHoldDuration", r.TemporaryHoldDuration, DbType.Int32);
        p.Add("@FairAccessEnabled", r.FairAccessEnabled, DbType.Boolean);
        p.Add("@WaitlistEnabled", r.WaitlistEnabled, DbType.Boolean);
        p.Add("@SalesPaused", r.SalesPaused, DbType.Boolean);
        p.Add("@CancellationPolicy", r.CancellationPolicy, DbType.String, size: 500);
        p.Add("@RefundPolicy", r.RefundPolicy, DbType.String, size: 500);
        p.Add("@CancellationDeadlineHours", r.CancellationDeadlineHours, DbType.Int32);
        p.Add("@RefundPercentage", r.RefundPercentage, DbType.Decimal);
        await conn.ExecuteAsync("sp_UpdateConcert", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateConcertStatusAsync(int concertId, int actorUserId, string status)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@NewStatus", status, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_UpdateConcertStatus", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> CreateVenueAsync(int actorUserId, CreateVenueRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueName", r.VenueName, DbType.String, size: 255);
        p.Add("@Address", r.Address, DbType.String, size: 500);
        p.Add("@NewVenueID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateVenue", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewVenueID");
    }

    public async Task<int> CreateZoneAsync(int actorUserId, int venueId, CreateZoneRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueID", venueId, DbType.Int32);
        p.Add("@ZoneCode", r.ZoneCode, DbType.AnsiString, size: 64);
        p.Add("@ZoneName", r.ZoneName, DbType.String, size: 255);
        p.Add("@ZoneType", r.ZoneType, DbType.AnsiString, size: 24);
        p.Add("@ZoneLevel", r.ZoneLevel, DbType.Int32);
        p.Add("@ZoneX", r.ZoneX, DbType.Int32);
        p.Add("@ZoneY", r.ZoneY, DbType.Int32);
        p.Add("@ZoneWidth", r.ZoneWidth, DbType.Int32);
        p.Add("@ZoneHeight", r.ZoneHeight, DbType.Int32);
        p.Add("@ZoneRotation", r.ZoneRotation, DbType.Decimal);
        p.Add("@ZoneCapacity", r.ZoneCapacity, DbType.Int32);
        p.Add("@NewZoneID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateZone", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewZoneID");
    }

    public async Task<int> CreateSeatAsync(int actorUserId, int zoneId, CreateSeatRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ZoneID", zoneId, DbType.Int32);
        p.Add("@SeatCode", r.SeatCode, DbType.AnsiString, size: 64);
        p.Add("@SeatLabel", r.SeatLabel, DbType.String, size: 255);
        p.Add("@SeatRowLabel", r.SeatRowLabel, DbType.String, size: 16);
        p.Add("@SeatColumnNumber", r.SeatColumnNumber, DbType.Int32);
        p.Add("@NewSeatID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateSeat", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewSeatID");
    }

    public async Task CreateSeatsBatchAsync(int actorUserId, int zoneId, CreateSeatsBatchRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var seatsJson = JsonSerializer.Serialize(r.Seats.Select(s => new
        {
            seatCode = s.SeatCode,
            seatLabel = s.SeatLabel,
            seatRowLabel = s.SeatRowLabel,
            seatColumnNumber = s.SeatColumnNumber,
        }));
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ZoneID", zoneId, DbType.Int32);
        p.Add("@SeatsJson", seatsJson, DbType.String);
        await conn.ExecuteAsync("sp_CreateSeatsBatch", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> ConfigureTicketCategoryAsync(int actorUserId, int concertId, ConfigureTicketCategoryRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@CategoryName", r.CategoryName, DbType.String, size: 255);
        p.Add("@CategoryDescription", r.CategoryDescription, DbType.String, size: 500);
        // BasePrice là nguồn sự thật của giá vé (BR10a) — bắt buộc, cascade xuống EventSeat.SalePrice.
        p.Add("@BasePrice", r.BasePrice, DbType.Decimal);
        // FR12: Active | Inactive. NULL = giữ nguyên (cập nhật) / 'Active' (tạo mới).
        p.Add("@CategoryStatus", r.CategoryStatus, DbType.AnsiString, size: 32);
        // @TicketCategoryID vừa là input (NULL = tạo mới, có giá trị = cập nhật) vừa là output.
        p.Add("@TicketCategoryID", r.TicketCategoryId, dbType: DbType.Int32,
              direction: ParameterDirection.InputOutput);
        await conn.ExecuteAsync("sp_ConfigureTicketCategory", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@TicketCategoryID");
    }

    public async Task AddEventSeatsAsync(int actorUserId, int concertId, AddEventSeatsRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@TicketCategoryID", r.TicketCategoryId, DbType.Int32);
        // Không truyền giá: SalePrice của EventSeat lấy từ TicketCategory.BasePrice (BR10a),
        // được sp_AddEventSeats gán và TRG_EventSeat_PriceInsert canh giữ.
        p.Add("@SeatIDs", string.Join(",", r.SeatIds), DbType.String, size: -1);
        await conn.ExecuteAsync("sp_AddEventSeats", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<int> CreatePromotionAsync(int actorUserId, int concertId, CreatePromotionRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@PromotionName", r.PromotionName, DbType.String, size: 255);
        p.Add("@PromotionDescription", r.PromotionDescription, DbType.String, size: 500);
        p.Add("@DiscountType", r.DiscountType, DbType.AnsiString, size: 32);
        p.Add("@DiscountValue", r.DiscountValue, DbType.Decimal);
        p.Add("@StartDatetime", r.StartDatetime, DbType.DateTime2);
        p.Add("@EndDatetime", r.EndDatetime, DbType.DateTime2);
        p.Add("@UsageLimit", r.UsageLimit, DbType.Int32);
        p.Add("@CodeRequiredFlag", r.CodeRequiredFlag, DbType.Boolean);
        p.Add("@MaxApplicableQuantity", r.MaxApplicableQuantity, DbType.Int32);
        p.Add("@MaxDiscountAmount", r.MaxDiscountAmount, DbType.Decimal);
        p.Add("@NewPromotionID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreatePromotion", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewPromotionID");
    }

    public async Task<int> CreateArtistAsync(int actorUserId, CreateArtistRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ArtistName", r.ArtistName, DbType.String, size: 255);
        p.Add("@ArtistDescription", r.ArtistDescription, DbType.String, size: 500);
        p.Add("@NewArtistID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateArtist", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewArtistID");
    }

    public async Task UpdateArtistAsync(int actorUserId, int artistId, UpdateArtistRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ArtistID", artistId, DbType.Int32);
        p.Add("@ArtistName", r.ArtistName, DbType.String, size: 255);
        p.Add("@ArtistDescription", r.ArtistDescription, DbType.String, size: 500);
        p.Add("@ArtistStatus", r.ArtistStatus, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_UpdateArtist", p, commandType: CommandType.StoredProcedure);
    }

    public async Task AssignRoleAsync(int actorUserId, AssignRoleRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TargetUserID", r.TargetUserId, DbType.Int32);
        p.Add("@RoleName", r.RoleName, DbType.String, size: 255);
        p.Add("@GrantOrRevoke", r.GrantOrRevoke, DbType.AnsiString, size: 10);
        await conn.ExecuteAsync("sp_AssignRole", p, commandType: CommandType.StoredProcedure);
    }

    // ── Admin/Organizer extended management (BP3/BP9/BP12/BP13) ───────────────

    public async Task<int> CreateDiscountCodeAsync(int actorUserId, int promotionId, CreateDiscountCodeRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@PromotionID", promotionId, DbType.Int32);
        p.Add("@CodeValue", r.CodeValue, DbType.AnsiString, size: 64);
        p.Add("@ValidFromDatetime", r.ValidFromDatetime, DbType.DateTime2);
        p.Add("@ValidToDatetime", r.ValidToDatetime, DbType.DateTime2);
        p.Add("@GlobalUsageLimit", r.GlobalUsageLimit, DbType.Int32);
        p.Add("@PerCustomerUsageLimit", r.PerCustomerUsageLimit, DbType.Int32);
        p.Add("@NewDiscountCodeID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateDiscountCode", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewDiscountCodeID");
    }

    public async Task SetEventSeatUnavailableAsync(int actorUserId, int eventSeatId, SetEventSeatUnavailableRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@EventSeatID", eventSeatId, DbType.Int32);
        p.Add("@Unavailable", r.Unavailable, DbType.Boolean);
        p.Add("@Reason", r.Reason, DbType.String, size: 500);
        await conn.ExecuteAsync("sp_SetEventSeatUnavailable", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateUserStatusAsync(int actorUserId, int targetUserId, UpdateUserStatusRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TargetUserID", targetUserId, DbType.Int32);
        p.Add("@NewStatus", r.Status, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_AdminUpdateUserStatus", p, commandType: CommandType.StoredProcedure);
    }

    public async Task AddCheckinStaffAssignmentAsync(int actorUserId, AddCheckinStaffAssignmentRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@StaffUserID", r.StaffUserId, DbType.Int32);
        p.Add("@ConcertIDs", string.Join(",", r.ConcertIds), DbType.String, size: -1);
        // BR39/FR51: 'Active' = phân công, 'Revoked' = thu hồi.
        p.Add("@AssignmentStatus", r.AssignmentStatus, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_AddCheckinStaffAssignment", p, commandType: CommandType.StoredProcedure);
    }

    // ── Vòng đời dữ liệu danh mục (FR59b / BR50e) ────────────────────────────

    public async Task UpdateVenueAsync(int actorUserId, int venueId, UpdateVenueRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueID", venueId, DbType.Int32);
        p.Add("@VenueName", r.VenueName, DbType.String, size: 255);
        p.Add("@Address", r.Address, DbType.String, size: 500);
        p.Add("@VenueStatus", r.VenueStatus, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_UpdateVenue", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateZoneAsync(int actorUserId, int zoneId, UpdateZoneRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ZoneID", zoneId, DbType.Int32);
        p.Add("@ZoneName", r.ZoneName, DbType.String, size: 255);
        p.Add("@ZoneDescription", r.ZoneDescription, DbType.String, size: 500);
        p.Add("@ZoneStatus", r.ZoneStatus, DbType.AnsiString, size: 32);
        p.Add("@ZoneType", r.ZoneType, DbType.AnsiString, size: 24);
        p.Add("@ZoneLevel", r.ZoneLevel, DbType.Int32);
        p.Add("@ZoneX", r.ZoneX, DbType.Int32);
        p.Add("@ZoneY", r.ZoneY, DbType.Int32);
        p.Add("@ZoneWidth", r.ZoneWidth, DbType.Int32);
        p.Add("@ZoneHeight", r.ZoneHeight, DbType.Int32);
        p.Add("@ZoneRotation", r.ZoneRotation, DbType.Decimal);
        p.Add("@ZoneCapacity", r.ZoneCapacity, DbType.Int32);
        p.Add("@ClearGeometry", r.ClearGeometry, DbType.Boolean);
        await conn.ExecuteAsync("sp_UpdateZone", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateSeatAsync(int actorUserId, int seatId, UpdateSeatRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@SeatID", seatId, DbType.Int32);
        p.Add("@SeatLabel", r.SeatLabel, DbType.String, size: 255);
        p.Add("@SeatStatus", r.SeatStatus, DbType.AnsiString, size: 32);
        p.Add("@SeatRowLabel", r.SeatRowLabel, DbType.String, size: 16);
        p.Add("@SeatColumnNumber", r.SeatColumnNumber, DbType.Int32);
        await conn.ExecuteAsync("sp_UpdateSeat", p, commandType: CommandType.StoredProcedure);
    }

    /// <summary>
    /// Khai báo mặt phẳng toạ độ và vị trí sân khấu của địa điểm (FR11a).
    ///
    /// Tách khỏi UpdateVenueAsync vì đây là mối quan tâm khác hẳn: nó có bộ kiểm
    /// tra riêng ở stored procedure (sân khấu phải nằm trong mặt phẳng; mặt phẳng
    /// không được thu nhỏ hơn vùng các khu đang chiếm) và được gọi với tần suất
    /// khác hẳn việc đổi tên hay địa chỉ.
    /// </summary>
    public async Task ConfigureVenueMapAsync(int actorUserId, int venueId, ConfigureVenueMapRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@VenueID", venueId, DbType.Int32);
        p.Add("@MapWidth", r.MapWidth, DbType.Int32);
        p.Add("@MapHeight", r.MapHeight, DbType.Int32);
        p.Add("@StageX", r.StageX, DbType.Int32);
        p.Add("@StageY", r.StageY, DbType.Int32);
        p.Add("@StageWidth", r.StageWidth, DbType.Int32);
        p.Add("@StageHeight", r.StageHeight, DbType.Int32);
        p.Add("@ClearStage", r.ClearStage, DbType.Boolean);
        p.Add("@ClearMap", r.ClearMap, DbType.Boolean);
        await conn.ExecuteAsync("sp_ConfigureVenueMap", p, commandType: CommandType.StoredProcedure);
    }

    // ── Cấu hình Fair Access / Waitlist theo Concert (FR64a, BR43, BR45b, BR47b) ──

    public async Task ConfigureQueueAsync(int actorUserId, int concertId, ConfigureQueueRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@AdmissionCapacity", r.AdmissionCapacity, DbType.Int32);
        p.Add("@FairAccessPolicy", r.FairAccessPolicy, DbType.AnsiString, size: 32);
        p.Add("@AdmissionValiditySeconds", r.AdmissionValiditySeconds, DbType.Int32);
        p.Add("@InheritGlobalAdmissionValidity", r.InheritGlobalAdmissionValidity, DbType.Boolean);
        p.Add("@QueueStatus", r.QueueStatus, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_ConfigureQueue", p, commandType: CommandType.StoredProcedure);
    }

    public async Task ConfigureWaitlistAsync(int actorUserId, int concertId, ConfigureWaitlistRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@AllocationPolicy", r.AllocationPolicy, DbType.AnsiString, size: 32);
        p.Add("@WaitlistStatus", r.WaitlistStatus, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_ConfigureWaitlist", p, commandType: CommandType.StoredProcedure);
    }

    // ── Vòng đời khuyến mãi / mã giảm giá (FR52, FR53b) ──────────────────────

    public async Task UpdateRoleStatusAsync(int actorUserId, string roleName, string status)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        // size 255 = dung do rong cua Role.RoleName NVARCHAR(255); khai bao rong hon
        // se khien Dapper gui tham so dai hon cot va SQL Server phai chuyen kieu.
        p.Add("@RoleName", roleName, DbType.String, size: 255);
        p.Add("@RoleStatus", status, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_UpdateRoleStatus", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdatePromotionStatusAsync(int actorUserId, int promotionId, string status)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@PromotionID", promotionId, DbType.Int32);
        p.Add("@NewStatus", status, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_UpdatePromotionStatus", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateDiscountCodeStatusAsync(int actorUserId, int discountCodeId, string status)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@DiscountCodeID", discountCodeId, DbType.Int32);
        p.Add("@NewStatus", status, DbType.AnsiString, size: 32);
        await conn.ExecuteAsync("sp_UpdateDiscountCodeStatus", p, commandType: CommandType.StoredProcedure);
    }
}
