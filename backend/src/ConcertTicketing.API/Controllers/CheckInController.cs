using System.Security.Claims;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.RateLimiting;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.API.Controllers;

[ApiController]
[Route("api/checkin")]
[Authorize(Roles = "Check-in Staff")]
public class CheckInController : ControllerBase
{
    private readonly ICheckInRepository _checkInRepository;

    public CheckInController(ICheckInRepository checkInRepository)
    {
        _checkInRepository = checkInRepository;
    }

    /// <summary>Soát vé tại cổng — gọi sp_CheckInTicket</summary>
    [HttpPost]
    [EnableRateLimiting("checkin")]
    [ProducesResponseType(typeof(CheckInResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> CheckIn([FromBody] CheckInRequest request)
    {
        // StaffUserID lấy từ JWT — không nhận từ request body
        var staffUserId = GetCurrentUserId();
        var result      = await _checkInRepository.CheckInAsync(staffUserId, request);

        // Luôn trả 200 — SP tự ghi Audit kể cả khi INVALID/ALREADY_USED
        // Frontend dùng result.ValidationResult để hiển thị màu xanh/đỏ
        return Ok(result);
    }

    private int GetCurrentUserId()
    {
        var sub = User.FindFirstValue(ClaimTypes.NameIdentifier)
               ?? User.FindFirstValue("sub")
               ?? throw new UnauthorizedAccessException("Token không hợp lệ.");
        return int.Parse(sub);
    }
}
