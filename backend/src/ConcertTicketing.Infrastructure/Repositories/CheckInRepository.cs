using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;

using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;



public class CheckInRepository : ICheckInRepository
{
    private readonly string _connectionString;

    public CheckInRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<CheckInResponse> CheckInAsync(int staffUserId, CheckInRequest request)
    {
        using var conn = new SqlConnection(_connectionString);

        var p = new DynamicParameters();
        p.Add("@TicketCode",          request.TicketCode,  DbType.String,  size: 100);
        p.Add("@ConcertID",           request.ConcertId,   DbType.Int32);
        p.Add("@CheckInStaffUserID",  staffUserId,         DbType.Int32);
        p.Add("@ValidationResult",    dbType: DbType.String, size: 32,  direction: ParameterDirection.Output);
        p.Add("@ValidationInfo",      dbType: DbType.String, size: 500, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_CheckInTicket", p,
            commandType: CommandType.StoredProcedure);

        var result = p.Get<string>("@ValidationResult");
        var info   = p.Get<string>("@ValidationInfo");

        return new CheckInResponse(
            result,
            info,
            result == "SUCCESS" ? DateTime.UtcNow : null);
    }
}