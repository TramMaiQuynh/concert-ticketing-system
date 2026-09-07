using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class AdminRepository : IAdminRepository
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
        p.Add("@ArtistID", r.ArtistId, DbType.Int32);
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
        p.Add("@ArtistID", r.ArtistId, DbType.Int32);
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
        p.Add("@NewStatus", status, DbType.String, size: 32);
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
        p.Add("@ZoneCode", r.ZoneCode, DbType.String, size: 64);
        p.Add("@ZoneName", r.ZoneName, DbType.String, size: 255);
        p.Add("@ZoneType", r.ZoneType, DbType.String, size: 24);
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
        p.Add("@SeatCode", r.SeatCode, DbType.String, size: 64);
        p.Add("@SeatLabel", r.SeatLabel, DbType.String, size: 255);
        p.Add("@SeatRowLabel", r.SeatRowLabel, DbType.String, size: 16);
        p.Add("@SeatColumnNumber", r.SeatColumnNumber, DbType.Int32);
        p.Add("@NewSeatID", dbType: DbType.Int32, direction: ParameterDirection.Output);
        await conn.ExecuteAsync("sp_CreateSeat", p, commandType: CommandType.StoredProcedure);
        return p.Get<int>("@NewSeatID");
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
        p.Add("@CategoryStatus", r.CategoryStatus, DbType.String, size: 32);
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
        p.Add("@DiscountType", r.DiscountType, DbType.String, size: 32);
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
        p.Add("@ArtistStatus", r.ArtistStatus, DbType.String, size: 32);
        await conn.ExecuteAsync("sp_UpdateArtist", p, commandType: CommandType.StoredProcedure);
    }

    public async Task AssignRoleAsync(int actorUserId, AssignRoleRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@TargetUserID", r.TargetUserId, DbType.Int32);
        p.Add("@RoleName", r.RoleName, DbType.String, size: 255);
        p.Add("@GrantOrRevoke", r.GrantOrRevoke, DbType.String, size: 10);
        await conn.ExecuteAsync("sp_AssignRole", p, commandType: CommandType.StoredProcedure);
    }

    // ── Admin/Organizer extended management (BP3/BP9/BP12/BP13) ───────────────

    public async Task<int> CreateDiscountCodeAsync(int actorUserId, int promotionId, CreateDiscountCodeRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@PromotionID", promotionId, DbType.Int32);
        p.Add("@CodeValue", r.CodeValue, DbType.String, size: 64);
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
        p.Add("@NewStatus", r.Status, DbType.String, size: 32);
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
        p.Add("@AssignmentStatus", r.AssignmentStatus, DbType.String, size: 32);
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
        p.Add("@VenueStatus", r.VenueStatus, DbType.String, size: 32);
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
        p.Add("@ZoneStatus", r.ZoneStatus, DbType.String, size: 32);
        p.Add("@ZoneType", r.ZoneType, DbType.String, size: 24);
        p.Add("@ZoneLevel", r.ZoneLevel, DbType.Int32);
        p.Add("@ZoneX", r.ZoneX, DbType.Int32);
        p.Add("@ZoneY", r.ZoneY, DbType.Int32);
        p.Add("@ZoneWidth", r.ZoneWidth, DbType.Int32);
        p.Add("@ZoneHeight", r.ZoneHeight, DbType.Int32);
        p.Add("@ZoneRotation", r.ZoneRotation, DbType.Decimal);
        p.Add("@ZoneCapacity", r.ZoneCapacity, DbType.Int32);
        await conn.ExecuteAsync("sp_UpdateZone", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateSeatAsync(int actorUserId, int seatId, UpdateSeatRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@SeatID", seatId, DbType.Int32);
        p.Add("@SeatLabel", r.SeatLabel, DbType.String, size: 255);
        p.Add("@SeatStatus", r.SeatStatus, DbType.String, size: 32);
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
        p.Add("@FairAccessPolicy", r.FairAccessPolicy, DbType.String, size: 32);
        p.Add("@AdmissionValiditySeconds", r.AdmissionValiditySeconds, DbType.Int32);
        p.Add("@InheritGlobalAdmissionValidity", r.InheritGlobalAdmissionValidity, DbType.Boolean);
        p.Add("@QueueStatus", r.QueueStatus, DbType.String, size: 32);
        await conn.ExecuteAsync("sp_ConfigureQueue", p, commandType: CommandType.StoredProcedure);
    }

    public async Task ConfigureWaitlistAsync(int actorUserId, int concertId, ConfigureWaitlistRequest r)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@AllocationPolicy", r.AllocationPolicy, DbType.String, size: 32);
        p.Add("@WaitlistStatus", r.WaitlistStatus, DbType.String, size: 32);
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
        p.Add("@NewStatus", status, DbType.String, size: 32);
        await conn.ExecuteAsync("sp_UpdatePromotionStatus", p, commandType: CommandType.StoredProcedure);
    }

    public async Task UpdateDiscountCodeStatusAsync(int actorUserId, int discountCodeId, string status)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        p.Add("@DiscountCodeID", discountCodeId, DbType.Int32);
        p.Add("@NewStatus", status, DbType.String, size: 32);
        await conn.ExecuteAsync("sp_UpdateDiscountCodeStatus", p, commandType: CommandType.StoredProcedure);
    }
}