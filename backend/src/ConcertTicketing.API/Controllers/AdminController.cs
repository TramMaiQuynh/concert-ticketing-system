using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.API.Controllers;

/// <summary>
/// Nghiệp vụ quản trị: Concert, Venue, Zone, Seat, Ticket Category,
/// EventSeat, Promotion, Role assignment. Quyền được SP kiểm tra
/// (Organizer sở hữu / Admin).
/// </summary>
[ApiController]
[Route("api/admin")]
[Authorize(Roles = "Admin,Organizer")]
public class AdminController : ControllerBase
{
    private readonly IAdminRepository _admin;

    public AdminController(IAdminRepository admin)
    {
        _admin = admin;
    }

    // ── Đọc danh mục ─────────────────────────────────────────────────────────
    //
    // Ba endpoint dưới đây là thứ biến quyết định "Admin dựng sơ đồ một lần,
    // organizer các lần sau chỉ chọn lại" thành một luồng dùng được thật.
    // Trước đó controller này KHÔNG có endpoint GET nào, nên organizer không có
    // cách nào BIẾT địa điểm nào đang tồn tại — phải được đọc số hiệu qua kênh
    // khác. Cả hai vai trò đều đọc được; đây là danh mục dùng chung, không nhạy cảm.

    /// <summary>Danh sách địa điểm để chọn khi tạo concert.</summary>
    [HttpGet("venues")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ListVenues([FromQuery] bool includeInactive = false)
        => Ok(await _admin.ListVenuesAsync(includeInactive));

    /// <summary>Các khu của một địa điểm — xem trước bố cục trước khi chọn.</summary>
    [HttpGet("venues/{venueId:int}/zones")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ListVenueZones(int venueId)
        => Ok(await _admin.ListVenueZonesAsync(venueId));

    /// <summary>Danh sách nghệ sĩ để chọn khi tạo concert.</summary>
    [HttpGet("artists")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ListArtists([FromQuery] bool includeRetired = false)
        => Ok(await _admin.ListArtistsAsync(includeRetired));

    // ── Concert ──────────────────────────────────────────────────────────────

    [HttpPost("concerts")]
    public async Task<IActionResult> CreateConcert([FromBody] CreateConcertRequest request)
    {
        var actor = GetActorUserId();
        var id = await _admin.CreateConcertAsync(actor, request);
        return Created($"/api/admin/concerts/{id}", new IdResponse(id));
    }

    [HttpPut("concerts/{id:int}")]
    public async Task<IActionResult> UpdateConcert(int id, [FromBody] UpdateConcertRequest request)
    {
        var actor = GetActorUserId();
        await _admin.UpdateConcertAsync(id, actor, request);
        return NoContent();
    }

    [HttpPatch("concerts/{id:int}/status")]
    public async Task<IActionResult> UpdateConcertStatus(int id, [FromBody] UpdateConcertStatusRequest request)
    {
        var actor = GetActorUserId();
        await _admin.UpdateConcertStatusAsync(id, actor, request.Status);
        return NoContent();
    }

    // ── Venue / Zone / Seat ──────────────────────────────────────────────────

    [HttpPost("venues")]
    public async Task<IActionResult> CreateVenue([FromBody] CreateVenueRequest request)
    {
        var actor = GetActorUserId();
        var id = await _admin.CreateVenueAsync(actor, request);
        return Created($"/api/admin/venues/{id}", new IdResponse(id));
    }

    [HttpPost("venues/{venueId:int}/zones")]
    public async Task<IActionResult> CreateZone(int venueId, [FromBody] CreateZoneRequest request)
    {
        var actor = GetActorUserId();
        var id = await _admin.CreateZoneAsync(actor, venueId, request);
        return Created($"/api/admin/zones/{id}", new IdResponse(id));
    }

    [HttpPost("zones/{zoneId:int}/seats")]
    public async Task<IActionResult> CreateSeat(int zoneId, [FromBody] CreateSeatRequest request)
    {
        var actor = GetActorUserId();
        var id = await _admin.CreateSeatAsync(actor, zoneId, request);
        return Created($"/api/admin/seats/{id}", new IdResponse(id));
    }

    // ── Ticket Category & EventSeat ──────────────────────────────────────────

    [HttpPost("concerts/{concertId:int}/categories")]
    public async Task<IActionResult> ConfigureCategory(int concertId, [FromBody] ConfigureTicketCategoryRequest request)
    {
        var actor = GetActorUserId();
        var id = await _admin.ConfigureTicketCategoryAsync(actor, concertId, request);
        return Created($"/api/admin/categories/{id}", new IdResponse(id));
    }

    [HttpPost("concerts/{concertId:int}/event-seats")]
    public async Task<IActionResult> AddEventSeats(int concertId, [FromBody] AddEventSeatsRequest request)
    {
        var actor = GetActorUserId();
        await _admin.AddEventSeatsAsync(actor, concertId, request);
        return NoContent();
    }

    // ── Promotion ────────────────────────────────────────────────────────────

    [HttpPost("concerts/{concertId:int}/promotions")]
    public async Task<IActionResult> CreatePromotion(int concertId, [FromBody] CreatePromotionRequest request)
    {
        var actor = GetActorUserId();
        var id = await _admin.CreatePromotionAsync(actor, concertId, request);
        return Created($"/api/admin/promotions/{id}", new IdResponse(id));
    }

    // ── Role Assignment ──────────────────────────────────────────────────────

    [HttpPost("roles/assign")]
    public async Task<IActionResult> AssignRole([FromBody] AssignRoleRequest request)
    {
        var actor = GetActorUserId();
        await _admin.AssignRoleAsync(actor, request);
        return NoContent();
    }

    /// <summary>
    /// Mở hoặc đóng khả năng PHÂN CÔNG của một vai trò (§12.3.2). Đóng lại chỉ chặn
    /// việc gán vai trò cho người mới; người đang giữ vai trò vẫn làm việc bình thường
    /// — muốn thu hồi của một người cụ thể thì dùng POST roles/assign với "Revoke".
    /// Hai vai trò Customer và Admin không đóng được: hệ thống tự gán Customer khi
    /// đăng ký, và UAI01 đòi luôn còn ít nhất một Admin.
    /// </summary>
    [HttpPut("roles/status")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateRoleStatus([FromBody] UpdateRoleStatusRequest request)
    {
        await _admin.UpdateRoleStatusAsync(GetActorUserId(), request.RoleName, request.Status);
        return NoContent();
    }

    // ── Discount Code ──────────────────────────────────────────────────────────

    [HttpPost("promotions/{promotionId:int}/discount-codes")]
    public async Task<IActionResult> CreateDiscountCode(int promotionId, [FromBody] CreateDiscountCodeRequest request)
    {
        var actor = GetActorUserId();
        var id = await _admin.CreateDiscountCodeAsync(actor, promotionId, request);
        return Created($"/api/admin/discount-codes/{id}", new IdResponse(id));
    }

    // ── EventSeat Availability (BR08) ──────────────────────────────────────────

    [HttpPatch("event-seats/{eventSeatId:int}/availability")]
    public async Task<IActionResult> SetEventSeatUnavailable(int eventSeatId, [FromBody] SetEventSeatUnavailableRequest request)
    {
        var actor = GetActorUserId();
        await _admin.SetEventSeatUnavailableAsync(actor, eventSeatId, request);
        return NoContent();
    }

    // ── User Status — Admin only (BR52) ────────────────────────────────────────

    [HttpPatch("users/{userId:int}/status")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> UpdateUserStatus(int userId, [FromBody] UpdateUserStatusRequest request)
    {
        var actor = GetActorUserId();
        await _admin.UpdateUserStatusAsync(actor, userId, request);
        return NoContent();
    }

    // ── Check-in Staff Assignment — Admin only (BR39 / FR51) ───────────────────

    [HttpPost("checkin-staff-assignments")]
    [Authorize(Roles = "Admin")]
    public async Task<IActionResult> AddCheckinStaffAssignment([FromBody] AddCheckinStaffAssignmentRequest request)
    {
        var actor = GetActorUserId();
        await _admin.AddCheckinStaffAssignmentAsync(actor, request);
        return NoContent();
    }

    // ── Artist (danh mục dùng chung — chỉ Admin, §12.6.1) ────────────────────

    /// <summary>
    /// Tạo Artist. Chỉ Admin: Artist dùng chung giữa mọi Organizer, nếu ai cũng tạo
    /// được sẽ sinh ra nhiều biến thể của cùng một nghệ sĩ và làm hỏng tìm kiếm/báo cáo.
    /// </summary>
    [HttpPost("artists")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(typeof(IdResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    public async Task<IActionResult> CreateArtist([FromBody] CreateArtistRequest request)
    {
        var id = await _admin.CreateArtistAsync(GetActorUserId(), request);
        return CreatedAtAction(nameof(CreateArtist), new { id }, new IdResponse(id));
    }

    /// <summary>
    /// Cập nhật Artist, đồng thời là đường chuyển sang Retired để ngừng sử dụng
    /// mà không xóa vật lý (BR50e, FR59b) — Artist bị Concert lịch sử tham chiếu.
    /// </summary>
    [HttpPut("artists/{artistId:int}")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateArtist(int artistId, [FromBody] UpdateArtistRequest request)
    {
        await _admin.UpdateArtistAsync(GetActorUserId(), artistId, request);
        return NoContent();
    }

    // ── Vòng đời dữ liệu danh mục (FR59b / BR50e) ────────────────────────────
    // Venue/Zone/Seat bị EventSeat và Ticket lịch sử tham chiếu nên không thể xóa
    // vật lý; ngừng sử dụng phải đi qua trạng thái. Trước đây ba trạng thái
    // Inactive/Retired tồn tại trong lược đồ nhưng không có endpoint nào đặt được.

    /// <summary>
    /// Khai báo mặt phẳng toạ độ và vị trí sân khấu của địa điểm (FR11a).
    ///
    /// Đây là bước biến một danh sách khu thành một sơ đồ có nghĩa: không có mặt
    /// phẳng và sân khấu thì không thể nói chỗ ngồi nào gần sân khấu hơn chỗ nào,
    /// mà đó lại chính là yếu tố quyết định giá trị một chiếc vé.
    ///
    /// Đơn vị là số nguyên trừu tượng — giao diện co giãn sơ đồ vào khung hình
    /// đang có, nên không cần dữ liệu đo đạc thực địa.
    /// </summary>
    [HttpPut("venues/{venueId:int}/map")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status401Unauthorized)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> ConfigureVenueMap(int venueId, [FromBody] ConfigureVenueMapRequest request)
    {
        var actor = GetActorUserId();
        await _admin.ConfigureVenueMapAsync(actor, venueId, request);
        return NoContent();
    }

    /// <summary>Cập nhật Venue; VenueStatus = 'Inactive' để ngừng sử dụng.</summary>
    [HttpPut("venues/{venueId:int}")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateVenue(int venueId, [FromBody] UpdateVenueRequest request)
    {
        await _admin.UpdateVenueAsync(GetActorUserId(), venueId, request);
        return NoContent();
    }

    /// <summary>Cập nhật Zone; ZoneStatus = 'Retired' để ngừng sử dụng.</summary>
    [HttpPut("zones/{zoneId:int}")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateZone(int zoneId, [FromBody] UpdateZoneRequest request)
    {
        await _admin.UpdateZoneAsync(GetActorUserId(), zoneId, request);
        return NoContent();
    }

    /// <summary>Cập nhật Seat; SeatStatus = 'Retired' cho ghế đã tháo dỡ (FR11).</summary>
    [HttpPut("seats/{seatId:int}")]
    [Authorize(Roles = "Admin")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdateSeat(int seatId, [FromBody] UpdateSeatRequest request)
    {
        await _admin.UpdateSeatAsync(GetActorUserId(), seatId, request);
        return NoContent();
    }

    // ── Cấu hình Fair Access / Waitlist theo Concert (FR64a) ─────────────────

    /// <summary>
    /// Cấu hình Virtual Queue của Concert: admission_capacity, queue_strategy
    /// (FIFO/RANDOM — BR45b) và booking_ttl (BR47b). Trước đây Queue chỉ được tạo
    /// ngầm bởi người đầu tiên vào hàng với FIFO cứng, nên RANDOM không đạt tới được.
    /// </summary>
    [HttpPut("concerts/{concertId:int}/queue")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> ConfigureQueue(int concertId, [FromBody] ConfigureQueueRequest request)
    {
        await _admin.ConfigureQueueAsync(GetActorUserId(), concertId, request);
        return NoContent();
    }

    /// <summary>Cấu hình Waitlist của Concert: allocation policy FIFO/RANDOM (BR43).</summary>
    [HttpPut("concerts/{concertId:int}/waitlist")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> ConfigureWaitlist(int concertId, [FromBody] ConfigureWaitlistRequest request)
    {
        await _admin.ConfigureWaitlistAsync(GetActorUserId(), concertId, request);
        return NoContent();
    }

    // ── Vòng đời khuyến mãi / mã giảm giá (FR52, FR53b) ──────────────────────

    /// <summary>
    /// Chuyển PromotionStatus giữa Draft / Active / Disabled. 'Expired' không còn
    /// trong miền giá trị: hết hạn là thuộc tính dẫn xuất từ EndDatetime.
    /// </summary>
    [HttpPut("promotions/{promotionId:int}/status")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> UpdatePromotionStatus(int promotionId, [FromBody] UpdatePromotionStatusRequest request)
    {
        await _admin.UpdatePromotionStatusAsync(GetActorUserId(), promotionId, request.Status);
        return NoContent();
    }

    /// <summary>
    /// Thu hồi (Disabled) hoặc khôi phục (Active) một mã giảm giá — đường duy nhất
    /// để chặn một mã đã bị rò rỉ khi nó vẫn còn trong khoảng ValidFrom/ValidTo.
    /// </summary>
    [HttpPut("discount-codes/{discountCodeId:int}/status")]
    [Authorize(Roles = "Admin,Organizer")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status403Forbidden)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> UpdateDiscountCodeStatus(int discountCodeId, [FromBody] UpdateDiscountCodeStatusRequest request)
    {
        await _admin.UpdateDiscountCodeStatusAsync(GetActorUserId(), discountCodeId, request.Status);
        return NoContent();
    }

    // ── Helper ───────────────────────────────────────────────────────────────

    private int GetActorUserId()
    {
        var sub = User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirstValue("sub")
               ?? throw new UnauthorizedAccessException("Token không hợp lệ.");
        return int.Parse(sub);
    }
}