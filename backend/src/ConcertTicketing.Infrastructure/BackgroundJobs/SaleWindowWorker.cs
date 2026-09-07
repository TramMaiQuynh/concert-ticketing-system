using Dapper;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.BackgroundJobs;

/// <summary>
/// SIP5 — Tự động chuyển trạng thái bán vé theo lịch (BR10b / LI01b):
///   Published → OnSale khi tới SaleStartDatetime
///   OnSale → SaleClosed khi tới SaleEndDatetime
///
/// Không có tiến trình này thì Concert chỉ đổi trạng thái khi có người gọi tay,
/// tức cửa sổ bán vé đã cấu hình không có hiệu lực.
///
/// sp_ProcessSaleWindowTransitions dùng atomic conditional update (BR49a) nên an toàn
/// khi chạy lặp hoặc chồng lấp lượt trước — không cần khoá phân tán.
/// </summary>
public sealed class SaleWindowWorker : BackgroundService
{
    private readonly IDbConnectionFactory _factory;
    private readonly ILogger<SaleWindowWorker> _logger;

    // Chu kỳ 1 phút: đủ mịn cho mốc mở/đóng bán vé tính theo phút,
    // đủ thưa để không tạo tải đáng kể lên database.
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(1);

    public SaleWindowWorker(IDbConnectionFactory factory, ILogger<SaleWindowWorker> logger)
    {
        _factory = factory;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("SaleWindowWorker (SIP5) đã khởi động, chu kỳ {Interval}.", Interval);

        using var timer = new PeriodicTimer(Interval);
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var conn = await _factory.OpenForSystemAsync(stoppingToken);
                await conn.ExecuteAsync(new CommandDefinition(
                    "sp_ProcessSaleWindowTransitions",
                    commandType: System.Data.CommandType.StoredProcedure,
                    cancellationToken: stoppingToken));
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                break; // shutdown bình thường
            }
            catch (Exception ex)
            {
                // Nuốt lỗi có ghi log: một lượt hỏng không được làm chết worker,
                // lượt kế tiếp sẽ xử lý lại (SP idempotent theo BR49a).
                _logger.LogError(ex, "SIP5 sp_ProcessSaleWindowTransitions thất bại ở lượt này.");
            }
        }
    }
}
