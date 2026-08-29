using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Authorization;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;
using ConcertTicketing.Infrastructure.Cache;

namespace ConcertTicketing.API.Controllers;

[ApiController]
[Route("api/concerts")]
public class ConcertController : ControllerBase
{
    private readonly IConcertRepository _concertRepository;
    private readonly SeatMapCache _seatMapCache;

    public ConcertController(IConcertRepository concertRepository, SeatMapCache seatMapCache)
    {
        _concertRepository = concertRepository;
        _seatMapCache      = seatMapCache;
    }

    /// <summary>Danh sách concert (public, có phân trang)</summary>
    [HttpGet]
    [AllowAnonymous]
    [ProducesResponseType(typeof(IEnumerable<ConcertListItem>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetList(
        [FromQuery] int page     = 1,
        [FromQuery] int pageSize = 20,
        [FromQuery] string? status = null)
    {
        if (page < 1) page = 1;
        if (pageSize is < 1 or > 100) pageSize = 20;

        var items = await _concertRepository.GetListAsync(page, pageSize, status);
        return Ok(items);
    }

    /// <summary>Chi tiết concert</summary>
    [HttpGet("{id:int}")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(ConcertDetail), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetById(int id)
    {
        var concert = await _concertRepository.GetByIdAsync(id);
        if (concert is null) return NotFound();
        return Ok(concert);
    }

    /// <summary>Sơ đồ ghế ngồi (cached TTL 15s + mutex chống Stampede)</summary>
    [HttpGet("{id:int}/seats")]
    [AllowAnonymous]
    [ProducesResponseType(typeof(IEnumerable<SeatDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetSeats(int id, CancellationToken ct)
    {
        var seats = await _seatMapCache.GetSeatsAsync(id, ct);
        return Ok(seats);
    }
}
