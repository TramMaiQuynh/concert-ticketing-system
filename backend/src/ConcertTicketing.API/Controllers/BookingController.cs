using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.RateLimiting;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.API.Controllers;

[ApiController]
[Route("api/bookings")]
[Authorize]
public class BookingController : ControllerBase
{
    private readonly IBookingRepository _bookingRepository;

    public BookingController(IBookingRepository bookingRepository)
    {
        _bookingRepository = bookingRepository;
    }

    /// <summary>Tạo booking mới — gọi sp_CreateBooking</summary>
    [HttpPost]
    [Authorize(Roles = "Customer")]
    [EnableRateLimiting("booking")]   // 2 req/10s per UserID — chống double-click
    [ProducesResponseType(typeof(CreateBookingResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status422UnprocessableEntity)]
    public async Task<IActionResult> Create([FromBody] CreateBookingRequest request)
    {
        // UserID luôn lấy từ JWT Claims, không bao giờ từ request body
        var userId = GetCurrentUserId();
        var result = await _bookingRepository.CreateAsync(userId, request);
        return StatusCode(StatusCodes.Status201Created, result);
    }

    /// <summary>Xem chi tiết booking</summary>
    [HttpGet("{id:int}")]
    [ProducesResponseType(typeof(BookingDetail), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(int id)
    {
        var userId  = GetCurrentUserId();
        var booking = await _bookingRepository.GetByIdAsync(id, userId);
        if (booking is null) return NotFound();
        return Ok(booking);
    }

    /// <summary>Áp dụng mã khuyến mãi — gọi sp_ApplyPromotion</summary>
    [HttpPost("{id:int}/promotion")]
    [Authorize(Roles = "Customer")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ApplyPromotion(int id, [FromBody] ApplyPromotionRequest request)
    {
        var userId = GetCurrentUserId();
        await _bookingRepository.ApplyPromotionAsync(id, userId, request.DiscountCode);
        return NoContent();
    }

    /// <summary>Hủy booking</summary>
    [HttpDelete("{id:int}")]
    [Authorize(Roles = "Customer")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> Cancel(int id)
    {
        var userId = GetCurrentUserId();
        await _bookingRepository.CancelAsync(id, userId);
        return NoContent();
    }

    // ── Helpers ──────────────────────────────────────────────────────────────

    private int GetCurrentUserId()
    {
        var sub = User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirstValue("sub")
               ?? throw new UnauthorizedAccessException("Token không hợp lệ.");
        return int.Parse(sub);
    }
}
