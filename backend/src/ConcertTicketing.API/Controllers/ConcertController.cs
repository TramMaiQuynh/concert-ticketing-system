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
    private readonly ISeatMapCache _seatMapCache;

    public ConcertController(IConcertRepository concertRepository, ISeatMapCache seatMapCache)
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

    /// <summary>
    /// Sơ đồ chỗ ngồi của concert (FR11a).
    ///
    /// Khác <c>/seats</c> ở chỗ đây là một TÀI LIỆU HÌNH HỌC lồng nhau — địa điểm,
    /// khu, ghế — chứ không phải danh sách phẳng. Nó cho phép giao diện vẽ được vị
    /// trí thật của chỗ ngồi so với sân khấu, thay vì chỉ liệt kê mã ghế.
    ///
    /// Ẩn danh gọi được: khách phải xem được chỗ ngồi trước khi quyết định đăng nhập.
    /// </summary>
    [HttpGet("{id:int}/seatmap")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetSeatMap(int id)
    {
        var map = await _concertRepository.GetSeatMapAsync(id);
        return map is null ? NotFound() : Ok(map);
    }

    /// <summary>
    /// Muc hai cua so do: ghe ben trong MOT khu (FR11a).
    ///
    /// Chi tai khi nguoi dung bam vao khu do. Do la ly do endpoint tong quan
    /// khong mang ghe: 234 byte moi ghe nghia la mot arena 20.000 cho se tra ve
    /// 4,5 MB neu gop lam mot.
    /// </summary>
    [HttpGet("{id:int}/seatmap/zones/{zoneId:int}")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetSeatMapZone(int id, int zoneId)
    {
        var zone = await _concertRepository.GetSeatMapZoneAsync(id, zoneId);
        return zone is null ? NotFound() : Ok(zone);
    }
}
