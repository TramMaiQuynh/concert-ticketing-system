using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.API.Controllers;

[ApiController]
[Route("api/waitlist")]
[Authorize(Roles = "Customer")]
public class WaitlistController : ControllerBase
{
    private readonly IWaitlistRepository _waitlist;

    public WaitlistController(IWaitlistRepository waitlist)
    {
        _waitlist = waitlist;
    }

    /// <summary>Đăng ký Waitlist cho Concert (cần Concert bật Waitlist).</summary>
    [HttpPost("concerts/{concertId:int}/join")]
    [ProducesResponseType(typeof(WaitlistJoinResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Join(int concertId)
    {
        var customerId = GetCurrentUserId();
        var result = await _waitlist.JoinAsync(customerId, concertId);
        return Ok(result);
    }

    /// <summary>Xem trạng thái entry Waitlist của chính khách hàng.</summary>
    [HttpGet("concerts/{concertId:int}/me")]
    [ProducesResponseType(typeof(WaitlistEntryStatusDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetMyEntry(int concertId)
    {
        var customerId = GetCurrentUserId();
        var entry = await _waitlist.GetMyEntryAsync(customerId, concertId);
        if (entry is null) return NotFound();
        return Ok(entry);
    }

    private int GetCurrentUserId()
    {
        var sub = User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirstValue("sub")
               ?? throw new UnauthorizedAccessException("Token không hợp lệ.");
        return int.Parse(sub);
    }
}