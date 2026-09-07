using System.Text.Json;
using StackExchange.Redis;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace ConcertTicketing.Infrastructure.Cache;

/// <summary>
/// Cache cho Seat Map với TTL + khóa chống Cache Stampede: khi cache miss, chỉ một
/// luồng được phép chạm DB, các luồng còn lại chờ rồi dùng lại kết quả đó.
///
/// LƯU Ý VỀ PHẠM VI: khóa ở đây là khóa TRONG MỘT PROCESS. Nếu chạy nhiều instance,
/// mỗi instance vẫn có thể có một luồng chạm DB — muốn chặn triệt để phải dùng
/// distributed lock trên Redis (SET NX PX).
/// </summary>
public class SeatMapCache : ISeatMapCache
{
    private readonly IDatabase _redis;
    private readonly IServiceScopeFactory _scopeFactory;
    private readonly ILogger<SeatMapCache>? _logger;
    private readonly int _ttlSeconds;

    /// <summary>
    /// Khóa được CHIA LÀN theo cache key thay vì dùng một khóa duy nhất cho toàn bộ cache.
    ///
    /// Bản trước dùng đúng một <see cref="SemaphoreSlim"/> cho mọi concert: một lần cache
    /// miss của concert A chặn luôn cả cache miss của concert B, C, D — mỗi lượt phải chờ
    /// trọn một vòng truy vấn DB của concert khác. Đúng vào lúc mở bán nhiều sự kiện cùng
    /// lúc (chính là lúc cache có ích nhất) thì toàn bộ yêu cầu sơ đồ ghế bị xếp thành
    /// một hàng nối đuôi nhau. Mục đích của khóa là chống dồn tải LÊN CÙNG MỘT KHÓA, không
    /// phải tuần tự hóa mọi thứ.
    ///
    /// Dùng mảng làn cố định thay vì từ điển theo khóa: bộ nhớ có trần rõ ràng và không
    /// phát sinh bài toán dọn phần tử (xóa một semaphore đúng lúc luồng khác vừa lấy được
    /// nó là một lỗi tranh chấp kinh điển). Trả giá là thỉnh thoảng hai concert khác nhau
    /// rơi vào cùng làn — vẫn tốt hơn nhiều so với dồn tất cả vào một khóa.
    /// </summary>
    private const int LaneCount = 64;
    private static readonly SemaphoreSlim[] Lanes =
        Enumerable.Range(0, LaneCount).Select(_ => new SemaphoreSlim(1, 1)).ToArray();

    private static SemaphoreSlim LaneFor(string key)
        => Lanes[(uint)StringComparer.Ordinal.GetHashCode(key) % LaneCount];

    public SeatMapCache(IConnectionMultiplexer redis, IServiceScopeFactory scopeFactory,
                        int ttlSeconds = 15, ILogger<SeatMapCache>? logger = null)
    {
        _redis        = redis.GetDatabase();
        _scopeFactory = scopeFactory;
        _ttlSeconds   = ttlSeconds;
        _logger       = logger;
    }

    public async Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId, CancellationToken ct = default)
    {
        var cacheKey = $"concert:seats:{concertId}";

        // Fast path: cache hit
        if (TryRead(cacheKey, await TryGetAsync(cacheKey), out var hit))
            return hit;

        var lane = LaneFor(cacheKey);
        await lane.WaitAsync(ct);
        try
        {
            // Double-check sau khi vào khóa (luồng khác có thể đã nạp xong)
            if (TryRead(cacheKey, await TryGetAsync(cacheKey), out var second))
                return second;

            // Tạo Scope mới để resolve Scoped Dependencies (IConcertRepository) đúng chuẩn DI
            using var scope = _scopeFactory.CreateScope();
            var concertRepository = scope.ServiceProvider.GetRequiredService<IConcertRepository>();

            var seats = (await concertRepository.GetSeatsAsync(concertId)).ToList();

            await TrySetAsync(cacheKey, JsonSerializer.Serialize(seats));

            return seats;
        }
        finally
        {
            lane.Release();
        }
    }

    /// <summary>
    /// Đọc Redis một cách CHỊU LỖI: Redis không sẵn sàng thì coi như cache miss.
    ///
    /// Trước đây mọi lỗi kết nối Redis đều lan thẳng ra ngoài, nên khi Redis chưa chạy thì
    /// GET /api/concerts/{id}/seats trả HTTP 500 — và vì sơ đồ ghế là bước bắt buộc trước
    /// khi đặt vé, toàn bộ luồng mua vé chết theo. Đã tái hiện được đúng như vậy.
    ///
    /// Cache là bộ tăng tốc, KHÔNG phải nguồn sự thật: khi nó không dùng được, hệ thống
    /// phải chậm đi chứ không được ngừng hoạt động. Chính Program.cs cũng đã thể hiện ý
    /// định này khi thêm `abortConnect=false` để Redis chết không chặn khởi động — nhưng
    /// đường xử lý request lại không tôn trọng ý định đó.
    /// </summary>
    private async Task<RedisValue> TryGetAsync(string cacheKey)
    {
        try
        {
            return await _redis.StringGetAsync(cacheKey);
        }
        catch (RedisException ex)
        {
            _logger?.LogWarning(ex, "Không đọc được cache {CacheKey}; đọc thẳng từ database.", cacheKey);
            return RedisValue.Null;
        }
        catch (TimeoutException ex)
        {
            _logger?.LogWarning(ex, "Đọc cache {CacheKey} quá hạn; đọc thẳng từ database.", cacheKey);
            return RedisValue.Null;
        }
    }

    /// <summary>Ghi cache theo kiểu "được thì tốt" — không ghi được cũng không hỏng request.</summary>
    private async Task TrySetAsync(string cacheKey, string json)
    {
        try
        {
            await _redis.StringSetAsync(cacheKey, json, TimeSpan.FromSeconds(_ttlSeconds));
        }
        catch (Exception ex) when (ex is RedisException or TimeoutException)
        {
            _logger?.LogWarning(ex, "Không ghi được cache {CacheKey}; bỏ qua.", cacheKey);
        }
    }

    /// <summary>
    /// Đọc giá trị cache một cách phòng thủ. Một bản ghi hỏng hoặc thuộc phiên bản DTO cũ
    /// sẽ làm JsonSerializer ném exception; nếu để nó lan ra thì MỌI yêu cầu sơ đồ ghế của
    /// concert đó trả về lỗi cho tới khi hết TTL. Coi như cache miss và nạp lại từ DB là
    /// hành vi đúng: cache là bản sao có thể bỏ đi, không phải nguồn sự thật.
    /// </summary>
    private bool TryRead(string cacheKey, RedisValue cached, out IEnumerable<SeatDto> seats)
    {
        seats = Array.Empty<SeatDto>();
        if (!cached.HasValue) return false;

        try
        {
            var parsed = JsonSerializer.Deserialize<List<SeatDto>>(cached!);
            if (parsed is null) return false;
            seats = parsed;
            return true;
        }
        catch (JsonException ex)
        {
            _logger?.LogWarning(ex, "Bản ghi cache {CacheKey} không đọc được, nạp lại từ DB.", cacheKey);
            return false;
        }
    }
}
