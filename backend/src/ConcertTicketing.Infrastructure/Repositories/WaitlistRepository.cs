using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

/// <summary>
/// Nghiệp vụ Waitlist: đăng ký + xem trạng thái entry của chính Customer.
/// </summary>
public class WaitlistRepository : IWaitlistRepository
{
    private readonly string _connectionString;

    public WaitlistRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<WaitlistJoinResponse> JoinAsync(int customerUserId, int concertId)
    {
        using var conn = new SqlConnection(_connectionString);
        var p = new DynamicParameters();
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);
        p.Add("@ConcertID", concertId, DbType.Int32);
        p.Add("@NewWaitlistEntryID", dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_JoinWaitlist", p, commandType: CommandType.StoredProcedure);
        var entryId = p.Get<int>("@NewWaitlistEntryID");

        var pos = await conn.QuerySingleAsync<int>(
            "SELECT QueuePosition FROM WaitlistEntry WHERE WaitlistEntryID = @Id",
            new { Id = entryId });

        return new WaitlistJoinResponse(entryId, pos);
    }

    public async Task<WaitlistEntryStatusDto?> GetMyEntryAsync(int customerUserId, int concertId)
    {
        using var conn = new SqlConnection(_connectionString);
        var sql = @"
            SELECT
                we.WaitlistEntryID,
                we.EntryStatus,
                we.QueuePosition,
                we.JoinedTimestamp,
                we.OpportunityGrantedTimestamp,
                we.OpportunityExpiryTimestamp
            FROM WaitlistEntry we
            JOIN Waitlist w ON w.WaitlistID = we.WaitlistID
            WHERE we.CustomerUserID = @CustomerUserID
              AND w.ConcertID       = @ConcertID
              AND we.EntryStatus IN ('Active', 'Granted')
            ORDER BY we.WaitlistEntryID;";

        return await conn.QuerySingleOrDefaultAsync<WaitlistEntryStatusDto>(
            sql, new { CustomerUserID = customerUserId, ConcertID = concertId });
    }
}