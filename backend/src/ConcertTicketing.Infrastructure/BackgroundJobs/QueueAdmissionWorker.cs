using Dapper;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.BackgroundJobs;

/// <summary>
/// SIP3 — Fair Access / Virtual Queue admission (BR45–BR47b):
///   - Chuyển QueueEntry Waiting → Admitted tới khi đạt AdmissionCapacity
///   - Chuyển QueueEntry Admitted quá booking_ttl → Expired, giải phóng slot
///
/// Không có tiến trình này thì khách vào hàng đợi và KHÔNG BAO GIỜ được admission —
/// toàn bộ BP11 không hoạt động.
///
/// sp_ProcessQueueAdmission nhận @ConcertID nên worker phải quét từng Concert đang
/// mở bán và bật Fair Access. SP tự dùng sp_getapplock theo Concert nên hai lượt
/// chồng nhau không gây vượt capacity.
/// </summary>
public sealed class QueueAdmissionWorker : BackgroundService
{
    private readonly IDbConnectionFactory _factory;
    private readonly ILogger<QueueAdmissionWorker> _logger;

    // Chu kỳ 15 giây: hàng đợi mở bán cao điểm cần nhả slot nhanh, nếu để 1 phút
    // thì slot của người hết hạn bị bỏ trống quá lâu trong khi hàng nghìn người chờ.
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(15);

    public QueueAdmissionWorker(IDbConnectionFactory factory, ILogger<QueueAdmissionWorker> logger)
    {
        _factory = factory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("QueueAdmissionWorker (SIP3) đã khởi động, chu kỳ {Interval}.", Interval);

        using var timer = new PeriodicTimer(Interval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var conn = await _factory.OpenForSystemAsync(stoppingToken);

                // Chỉ quét Concert thực sự có Queue đang mở — tránh gọi SP vô ích.
                var concertIds = (await conn.QueryAsync<int>(new CommandDefinition(@"
                    SELECT q.ConcertID
                    FROM   Queue   q
                    JOIN   Concert c ON c.ConcertID = q.ConcertID
                    WHERE  q.QueueStatus     = 'Open'
                      AND  c.ConcertStatus   = 'OnSale'
                      AND  c.SalesPaused     = 0
                      AND  c.FairAccessEnabled = 1;",
                    cancellationToken: stoppingToken))).ToList();

                foreach (var concertId in concertIds)
                {
                    stoppingToken.ThrowIfCancellationRequested();
                    await conn.ExecuteAsync(new CommandDefinition(
                        "sp_ProcessQueueAdmission",
                        new { ConcertID = concertId },
                        commandType: System.Data.CommandType.StoredProcedure,
                        cancellationToken: stoppingToken));
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break; // shutdown bình thường
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "SIP3 sp_ProcessQueueAdmission thất bại ở lượt này.");
            }
        }
    }
}
