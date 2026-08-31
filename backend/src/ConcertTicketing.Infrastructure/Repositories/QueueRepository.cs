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
    private readonly string _connectionString;

    public QueueRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<JoinQueueResponse> JoinAsync(int customerUserId, int concertId)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@NewQueueEntryID", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_JoinQueue", p, commandType: CommandType.StoredProcedure);
        var entryId = p.Get<int>("@NewQueueEntryID");

        var dto = await conn.QuerySingleOrDefaultAsync<QueueEntryStatusDto>(
            "SELECT QueueEntryID, QueueStatus, JoinedTimestamp, AdmissionPosition, AdmissionExpiryTimestamp FROM QueueEntry WHERE QueueEntryID = @Id",
            new { Id = entryId });

        return new JoinQueueResponse(dto.QueueEntryId, dto.QueueStatus, dto.JoinedTimestamp);
    }

    public async Task<QueueEntryStatusDto?> GetMyEntryAsync(int customerUserId, int concertId)
    {
        using var conn = new SqlConnection(_connectionString);
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