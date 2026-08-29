using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Domain.Models;

using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;



public class BookingRepository : IBookingRepository
{
    private readonly string _connectionString;

    public BookingRepository(string connectionString)
    {
        _connectionString = connectionString;
    }

    public async Task<CreateBookingResponse> CreateAsync(int customerUserId, CreateBookingRequest request)
    {
        using var conn = new SqlConnection(_connectionString);

        var p = new DynamicParameters();
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);
        p.Add("@ConcertID",      request.ConcertId, DbType.Int32);
        p.Add("@SeatList",       string.Join(",", request.SeatIds), DbType.String, size: -1);
        p.Add("@WaitlistEntryID", request.WaitlistEntryId, DbType.Int32);
        p.Add("@NewBookingID",    dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_CreateBooking", p,
            commandType: CommandType.StoredProcedure);

        var newBookingId = p.Get<int>("@NewBookingID");

        // Lấy thông tin booking vừa tạo để trả về response đầy đủ
        var booking = await conn.QuerySingleAsync<Booking>(
            "SELECT * FROM Booking WHERE BookingID = @BookingID",
            new { BookingID = newBookingId });

        return new CreateBookingResponse(
            booking.BookingID,
            booking.BookingReference ?? string.Empty,
            booking.HoldExpiryDatetime ?? DateTime.UtcNow.AddMinutes(15),
            booking.SubtotalAmount,
            booking.FinalAmount,
            booking.BookingStatus);
    }

    public async Task<BookingDetail?> GetByIdAsync(int bookingId, int customerUserId)
    {
        using var conn = new SqlConnection(_connectionString);

        // Multi-query: lấy booking + allocations cùng lúc
        var sql = @"
            SELECT b.*, c.ConcertName
            FROM Booking b
            JOIN Concert c ON b.ConcertID = c.ConcertID
            WHERE b.BookingID = @BookingID AND b.CustomerUserID = @CustomerUserID;

            SELECT ba.SeatID, es.SeatNumber, es.SectionName, sc.CategoryName, ba.PriceAtBooking
            FROM BookingAllocation ba
            JOIN EventSeat es ON ba.SeatID = es.SeatID
            JOIN SeatCategory sc ON es.SeatCategoryID = sc.SeatCategoryID
            WHERE ba.BookingID = @BookingID;";

        using var multi = await conn.QueryMultipleAsync(sql,
            new { BookingID = bookingId, CustomerUserID = customerUserId });

        var row = await multi.ReadSingleOrDefaultAsync<dynamic>();
        if (row == null) return null;

        var allocations = (await multi.ReadAsync<BookingAllocationDto>()).ToList();

        return new BookingDetail(
            (int)row.BookingID,
            (int)row.ConcertID,
            (string)row.ConcertName,
            (string)row.BookingStatus,
            (DateTime)row.BookingDatetime,
            (DateTime?)row.HoldExpiryDatetime,
            (decimal)row.SubtotalAmount,
            (decimal)row.DiscountAmount,
            (decimal)row.FinalAmount,
            (string?)row.BookingReference,
            allocations);
    }

    public async Task CancelAsync(int bookingId, int customerUserId)
    {
        using var conn = new SqlConnection(_connectionString);
        // Hủy booking — kiểm tra owner trước để tránh IDOR
        var affected = await conn.ExecuteAsync(@"
            UPDATE Booking
            SET BookingStatus = 'Cancelled'
            WHERE BookingID = @BookingID
              AND CustomerUserID = @CustomerUserID
              AND BookingStatus = 'Pending'",
            new { BookingID = bookingId, CustomerUserID = customerUserId });

        if (affected == 0)
            throw new ArgumentException("Booking không tồn tại hoặc không thể hủy.");
    }

    public async Task ApplyPromotionAsync(int bookingId, int customerUserId, string discountCode)
    {
        using var conn = new SqlConnection(_connectionString);

        var p = new DynamicParameters();
        p.Add("@BookingID",    bookingId,    DbType.Int32);
        p.Add("@DiscountCode", discountCode, DbType.String, size: 50);
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);

        await conn.ExecuteAsync("sp_ApplyPromotion", p,
            commandType: CommandType.StoredProcedure);
    }
}