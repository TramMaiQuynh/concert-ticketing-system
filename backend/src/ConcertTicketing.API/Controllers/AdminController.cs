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

    // ── Helper ───────────────────────────────────────────────────────────────

    private int GetActorUserId()
    {
        var sub = User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirstValue("sub")
               ?? throw new UnauthorizedAccessException("Token không hợp lệ.");
        return int.Parse(sub);
    }
}