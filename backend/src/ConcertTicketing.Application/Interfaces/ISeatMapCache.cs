using ConcertTicketing.Application.DTOs;

namespace ConcertTicketing.Application.Interfaces;

public interface ISeatMapCache
{
    Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId, CancellationToken ct = default);
}
