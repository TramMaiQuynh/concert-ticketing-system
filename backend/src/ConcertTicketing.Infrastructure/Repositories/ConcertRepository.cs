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
                v.VenueName, v.City,
                c.ConcertDate, c.Status, c.SalesPaused,
                c.SaleStartDatetime, c.ImageUrl
            FROM Concert c
            JOIN Artist a ON c.ArtistID = a.ArtistID
            JOIN Venue  v ON c.VenueID  = v.VenueID
            WHERE (@Status IS NULL OR c.Status = @Status)
              AND c.Status != 'Draft'
            ORDER BY c.ConcertDate ASC
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
                v.VenueName, v.Address, v.City, v.Capacity,
                c.ConcertDate, c.Status, c.SalesPaused,
                c.SaleStartDatetime, c.SaleEndDatetime,
                c.PurchaseLimitPerCustomer, c.Description, c.ImageUrl
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
                es.SeatID, es.SeatNumber, es.SectionName, es.Row,
                sc.CategoryName,
                es.InventoryStatus,
                es.Price
            FROM EventSeat es
            JOIN SeatCategory sc ON es.SeatCategoryID = sc.SeatCategoryID
            WHERE es.ConcertID = @ConcertID
            ORDER BY es.SectionName, es.Row, es.SeatNumber;";

        return await conn.QueryAsync<SeatDto>(sql, new { ConcertID = concertId });
    }
}