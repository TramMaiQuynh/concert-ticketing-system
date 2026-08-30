using System.Text.Json;
using StackExchange.Redis;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Cache;

/// <summary>
/// Cache cho Seat Map với TTL + SemaphoreSlim Mutex.
/// Chỉ 1 luồng được phép query DB khi cache miss → chống Cache Stampede.
///
/// LƯU Ý: SemaphoreSlim chỉ hoạt động trong 1 process duy nhất.
/// Nếu scale lên nhiều instances, phải đổi sang Redis Distributed Lock (SET NX PX).
/// </summary>
public class SeatMapCache : ISeatMapCache
{
    private readonly IDatabase _redis;
    private readonly IConcertRepository _concertRepository;
    private readonly int _ttlSeconds;
    private readonly SemaphoreSlim _lock = new(1, 1);

    public SeatMapCache(IConnectionMultiplexer redis, IConcertRepository concertRepository, int ttlSeconds = 15)
    {
        _redis             = redis.GetDatabase();
        _concertRepository = concertRepository;
        _ttlSeconds        = ttlSeconds;
    }

    public async Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId, CancellationToken ct = default)
    {
        var cacheKey = $"concert:seats:{concertId}";

        // Fast path: cache hit
        var cached = await _redis.StringGetAsync(cacheKey);
        if (cached.HasValue)
            return JsonSerializer.Deserialize<IEnumerable<SeatDto>>(cached!)!;

        // Slow path: cache miss → chỉ 1 luồng được vào, phần còn lại chờ
        await _lock.WaitAsync(ct);
        try
        {
            // Double-check sau khi vào lock (luồng thứ 2 có thể đã có cache rồi)
            cached = await _redis.StringGetAsync(cacheKey);
            if (cached.HasValue)
                return JsonSerializer.Deserialize<IEnumerable<SeatDto>>(cached!)!;

            // Chỉ 1 luồng duy nhất chạm DB
            var seats = (await _concertRepository.GetSeatsAsync(concertId)).ToList();

            var json = JsonSerializer.Serialize(seats);
            await _redis.StringSetAsync(
                cacheKey,
                json,
                TimeSpan.FromSeconds(_ttlSeconds));

            return seats;
        }
        finally
        {
            _lock.Release();
        }
    }
}
