using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Domain.Models;

using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class ConcertRepository : IConcertRepository
{
    private readonly string _connectionString;

    public ConcertRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<IEnumerable<ConcertListItem>> GetListAsync(int page, int pageSize, string? status)
    {
        using var conn = new SqlConnection(_connectionString);

        var sql = @"
            SELECT
                c.ConcertID, c.ConcertName,
                a.ArtistName,
                v.VenueName, v.Address,
                c.StartDatetime, c.ConcertStatus, c.SalesPaused,
                c.SaleStartDatetime
            FROM Concert c
            JOIN Artist a ON c.ArtistID = a.ArtistID
            JOIN Venue  v ON c.VenueID  = v.VenueID
            WHERE (@Status IS NULL OR c.ConcertStatus = @Status)
              AND c.ConcertStatus != 'Draft'
            ORDER BY c.StartDatetime ASC
            OFFSET @Offset ROWS FETCH NEXT @PageSize ROWS ONLY;";

        return await conn.QueryAsync<ConcertListItem>(sql, new
        {
            Status   = status,
            Offset   = (page - 1) * pageSize,
            PageSize = pageSize
        });
    }

    public async Task<ConcertDetail?> GetByIdAsync(int concertId)
    {
        using var conn = new SqlConnection(_connectionString);

        var sql = @"
            SELECT
                c.ConcertID, c.ConcertName,
                a.ArtistName,
                v.VenueName, v.Address,
                c.StartDatetime, c.ConcertStatus, c.SalesPaused,
                c.SaleStartDatetime, c.SaleEndDatetime,
                c.PurchaseLimit
            FROM Concert c
            JOIN Artist a ON c.ArtistID = a.ArtistID
            JOIN Venue  v ON c.VenueID  = v.VenueID
            WHERE c.ConcertID = @ConcertID;";

        return await conn.QuerySingleOrDefaultAsync<ConcertDetail>(sql,
            new { ConcertID = concertId });
    }

    public async Task<IEnumerable<SeatDto>> GetSeatsAsync(int concertId)
    {
        using var conn = new SqlConnection(_connectionString);

        var sql = @"
            SELECT
                es.EventSeatID AS SeatID,
                s.SeatCode     AS SeatNumber,
                z.ZoneName     AS SectionName,
                s.SeatLabel    AS [Row],
                tc.CategoryName,
                es.InventoryStatus,
                es.SalePrice   AS Price
            FROM EventSeat es
            JOIN Seat            s  ON s.SeatID           = es.SeatID
            JOIN Zone            z  ON z.ZoneID           = s.ZoneID
            JOIN TicketCategory  tc ON tc.ConcertID       = es.ConcertID
                                   AND tc.TicketCategoryID = es.TicketCategoryID
            WHERE es.ConcertID = @ConcertID
            ORDER BY z.ZoneName, s.SeatCode;";

        return await conn.QueryAsync<SeatDto>(sql, new { ConcertID = concertId });
    }
}