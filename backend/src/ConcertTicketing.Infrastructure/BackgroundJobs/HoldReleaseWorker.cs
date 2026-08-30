using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace ConcertTicketing.Infrastructure.BackgroundJobs;

/// <summary>
/// Background worker định kỳ (mỗi 1 phút):
///   1. sp_ReleaseExpiredHolds  — nhả ghế hết hạn Hold về Available
///   2. sp_AllocateWaitlist     — cấp ghế vừa nhả cho người trong hàng đợi
///
/// Dùng IHostedService thay vì Hangfire vì:
///   - Không cần persistence (nếu app restart, SP chạy lại ở chu kỳ kế tiếp là OK)
///   - Không cần retry (SP là idempotent)
///   - Không cần dashboard riêng
///   - Không tạo thêm bảng Hangfire trong DB
/// </summary>
public class HoldReleaseWorker : BackgroundService
{
    private readonly string _connectionString;
    private readonly ILogger<HoldReleaseWorker> _logger;
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(1);

    public HoldReleaseWorker(string connectionString, ILogger<HoldReleaseWorker> logger)
    {
        _connectionString = connectionString;
        _logger           = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("HoldReleaseWorker đã khởi động, chu kỳ {Interval}.", Interval);

        using var timer = new PeriodicTimer(Interval);

        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                await ReleaseAndAllocateAsync(stoppingToken);
            }
            catch (OperationCanceledException)
            {
                // App đang shutdown — thoát vòng lặp bình thường
                break;
            }
            catch (Exception ex)
            {
                // Ghi log lỗi nhưng tiếp tục chạy, không crash worker
                _logger.LogError(ex, "HoldReleaseWorker gặp lỗi trong chu kỳ {Time}.", DateTime.UtcNow);
            }
        }

        _logger.LogInformation("HoldReleaseWorker đã dừng.");
    }

    private async Task ReleaseAndAllocateAsync(CancellationToken ct)
    {
        using var conn = new SqlConnection(_connectionString);
        await conn.OpenAsync(ct);

        // Bước 1: Nhả ghế hết hạn → trả về Available
        var released = await conn.ExecuteAsync(
            new CommandDefinition(
                "sp_ReleaseExpiredHolds",
                commandType: CommandType.StoredProcedure,
                cancellationToken: ct));

        _logger.LogDebug("sp_ReleaseExpiredHolds hoàn thành.");

        // Bước 2: Ngay lập tức cấp ghế vừa nhả cho người trong Waitlist
        var concertIds = await conn.QueryAsync<int>(
            new CommandDefinition(
                "SELECT ConcertID FROM Concert WHERE ConcertStatus = 'OnSale' AND SalesPaused = 0",
                cancellationToken: ct));

        foreach (var concertId in concertIds)
        {
            await conn.ExecuteAsync(
                new CommandDefinition(
                    "sp_AllocateWaitlist",
                    new { ConcertID = concertId },
                    commandType: CommandType.StoredProcedure,
                    cancellationToken: ct));
        }

        _logger.LogDebug("sp_AllocateWaitlist hoàn thành.");
    }
}
