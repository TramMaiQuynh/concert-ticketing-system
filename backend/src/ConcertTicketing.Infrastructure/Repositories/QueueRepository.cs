using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

/// <summary>
/// Nghiệp vụ Fair Access Queue (BP11 / FR64): Customer tham gia virtual queue
/// của Concert bật FairAccessEnabled và xem trạng thái entry của chính mình.
/// </summary>
public class QueueRepository : IQueueRepository
{
    private readonly IDbConnectionFactory _factory;

    public QueueRepository(IDbConnectionFactory factory)
    {
        _factory = factory;
    }

    public async Task<JoinQueueResponse> JoinAsync(int customerUserId, int concertId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@NewQueueEntryID", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_JoinQueue", p, commandType: CommandType.StoredProcedure);
        var entryId = p.Get<int>("@NewQueueEntryID");

        // QuerySingle (khong OrDefault): entry vua duoc SP tao nen PHAI ton tai —
        // neu khong, do la loi that su chu khong phai truong hop hop le tra null.
        var dto = await conn.QuerySingleAsync<QueueEntryStatusDto>(
            "SELECT QueueEntryID, QueueStatus, JoinedTimestamp, AdmissionPosition, AdmissionExpiryTimestamp FROM QueueEntry WHERE QueueEntryID = @Id",
            new { Id = entryId });

        return new JoinQueueResponse(dto.QueueEntryId, dto.QueueStatus, dto.JoinedTimestamp);
    }

    /// <summary>Customer chu dong roi hang doi (BP11 / BR48).</summary>
    public async Task ExitAsync(int queueEntryId, int actorUserId)
    {
        using var conn = await _factory.OpenAsync();
        var p = new DynamicParameters();
        p.Add("@QueueEntryID", queueEntryId, DbType.Int32);
        p.Add("@ActorUserID", actorUserId, DbType.Int32);
        await conn.ExecuteAsync("sp_ExitQueue", p, commandType: CommandType.StoredProcedure);
    }

    public async Task<QueueEntryStatusDto?> GetMyEntryAsync(int customerUserId, int concertId)
    {
        using var conn = await _factory.OpenAsync();
        var sql = @"
            SELECT
                qe.QueueEntryID,
                qe.QueueStatus,
                qe.JoinedTimestamp,
                qe.AdmissionPosition,
                qe.AdmissionExpiryTimestamp
            FROM QueueEntry qe
            JOIN Queue q ON q.QueueID = qe.QueueID
            WHERE qe.CustomerUserID = @CustomerUserID
              AND q.ConcertID       = @ConcertID
              AND qe.QueueStatus IN ('Waiting', 'Admitted')
            ORDER BY qe.QueueEntryID;";

        return await conn.QuerySingleOrDefaultAsync<QueueEntryStatusDto>(
            sql, new { CustomerUserID = customerUserId, ConcertID = concertId });
    }
}