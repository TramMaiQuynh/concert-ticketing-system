using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using System.Security.Claims;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.API.Controllers;

/// <summary>
/// Fair Access Queue (BP11 / FR64): Customer tham gia virtual queue cho Concert
/// có bật FairAccessEnabled và xem trạng thái entry của chính khách hàng.
/// </summary>
[ApiController]
[Route("api/queue")]
[Authorize(Roles = "Customer")]
public class QueueController : ControllerBase
{
    private readonly IQueueRepository _queue;

    public QueueController(IQueueRepository queue)
    {
        _queue = queue;
    }

    /// <summary>Tham gia Queue cho Concert (cần Concert bật Fair Access).</summary>
    [HttpPost("concerts/{concertId:int}/join")]
    [ProducesResponseType(typeof(JoinQueueResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public async Task<IActionResult> Join(int concertId)
    {
        var customerId = GetCurrentUserId();
        var result = await _queue.JoinAsync(customerId, concertId);
        return Ok(result);
    }

    /// <summary>Xem trạng thái entry Queue của chính khách hàng.</summary>
    [HttpGet("concerts/{concertId:int}/me")]
    [ProducesResponseType(typeof(QueueEntryStatusDto), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetMyEntry(int concertId)
    {
        var customerId = GetCurrentUserId();
        var entry = await _queue.GetMyEntryAsync(customerId, concertId);
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