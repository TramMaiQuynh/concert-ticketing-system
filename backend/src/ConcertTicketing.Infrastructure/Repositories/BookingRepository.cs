using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Domain.Models;

using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;

public class BookingRepository : IBookingRepository
{
    private readonly IDbConnectionFactory _factory;

    public BookingRepository(IDbConnectionFactory factory)
    {
        _factory = factory;
    }

    public async Task<CreateBookingResponse> CreateAsync(int customerUserId, CreateBookingRequest request)
    {
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);
        p.Add("@ConcertID",      request.ConcertId, DbType.Int32);
        p.Add("@SeatList",       string.Join(",", request.SeatIds), DbType.String, size: -1);
        p.Add("@WaitlistEntryID", request.WaitlistEntryId, DbType.Int32);
        p.Add("@NewBookingID",    dbType: DbType.Int32, direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_CreateBooking", p,
            commandType: CommandType.StoredProcedure);

        var newBookingId = p.Get<int>("@NewBookingID");

        var booking = await conn.QuerySingleAsync<Booking>(
            "SELECT * FROM Booking WHERE BookingID = @BookingID",
            new { BookingID = newBookingId });

        return new CreateBookingResponse(
            booking.BookingID,
            $"BKG-{booking.BookingID:D6}",
            booking.HoldExpiryDatetime ?? DateTime.UtcNow.AddMinutes(15),
            booking.SubtotalAmount,
            booking.FinalAmount,
            booking.BookingStatus);
    }

    public async Task<BookingDetail?> GetByIdAsync(int bookingId, int customerUserId)
    {
        using var conn = await _factory.OpenAsync();

        var sql = @"
            SELECT 
                b.*, 
                c.ConcertName,
                ISNULL((SELECT SUM(DiscountAmount) FROM BookingPromotionApplication WHERE BookingID = b.BookingID), 0) AS DiscountAmount
            FROM Booking b
            JOIN Concert c ON b.ConcertID = c.ConcertID
            WHERE b.BookingID = @BookingID AND b.CustomerUserID = @CustomerUserID;

            SELECT
                besa.EventSeatID AS SeatID,
                s.SeatCode       AS SeatNumber,
                z.ZoneName       AS SectionName,
                tc.CategoryName,
                besa.PriceSnapshot AS PriceAtBooking
            FROM BookingEventSeatAllocation besa
            JOIN EventSeat      es ON es.EventSeatID      = besa.EventSeatID
            JOIN Seat           s  ON s.SeatID            = es.SeatID
            JOIN Zone           z  ON z.ZoneID            = s.ZoneID
            JOIN TicketCategory tc ON tc.ConcertID        = es.ConcertID
                                   AND tc.TicketCategoryID = es.TicketCategoryID
            WHERE besa.BookingID = @BookingID;";

        using var multi = await conn.QueryMultipleAsync(sql,
            new { BookingID = bookingId, CustomerUserID = customerUserId });

        var row = await multi.ReadSingleOrDefaultAsync<dynamic>();
        if (row == null) return null;

        var allocations = (await multi.ReadAsync<BookingAllocationDto>()).ToList();

        // Chuyển đổi an toàn: HoldExpiryDatetime có thể NULL (booking không giữ)
        DateTime? holdExpiry = null;
        if (row.HoldExpiryDatetime != null)
            holdExpiry = (DateTime)row.HoldExpiryDatetime;

        return new BookingDetail(
            (int)row.BookingID,
            (int)row.ConcertID,
            (string)row.ConcertName,
            (string)row.BookingStatus,
            (DateTime)row.CreatedTimestamp,
            holdExpiry,
            (decimal)row.SubtotalAmount,
            (decimal)row.DiscountAmount,
            (decimal)row.FinalAmount,
            $"BKG-{row.BookingID:D6}",
            allocations);
    }

    /// <summary>
    /// Lịch sử đặt vé của chính Customer (FR50).
    ///
    /// Đọc qua VW_CustomerBookingHistory chứ không truy vấn thẳng bảng Booking: view này
    /// được tạo ra đúng cho mục đích đó và tự lọc bằng
    /// `CustomerUserID = SESSION_CONTEXT(N'UserID')` (§23.7). SqlConnectionFactory đặt
    /// session context ngay sau khi mở connection, nên phạm vi dữ liệu được thi hành ở
    /// tầng database — không phụ thuộc vào việc tầng ứng dụng có nhớ truyền đúng UserID
    /// vào mệnh đề WHERE hay không. Nếu context chưa được đặt, view trả 0 dòng
    /// (fail-closed), không bao giờ rò rỉ dữ liệu của người khác.
    ///
    /// Trước đây view này KHÔNG có bên đọc nào — cơ chế RLS tồn tại nhưng không phục vụ
    /// chức năng nào (§24.4: mọi đường dữ liệu phải có cả bên ghi lẫn bên gọi).
    /// </summary>
    public async Task<IEnumerable<MyBookingListItem>> GetMyBookingsAsync()
    {
        using var conn = await _factory.OpenAsync();

        return await conn.QueryAsync<MyBookingListItem>(@"
            SELECT BookingID, ConcertID, ConcertName, BookingStatus,
                   CreatedTimestamp, HoldExpiryDatetime, ConfirmedTimestamp, CancelledTimestamp,
                   SubtotalAmount, FinalAmount, SeatCount, PaymentStatus
            FROM   VW_CustomerBookingHistory
            ORDER  BY CreatedTimestamp DESC;");
    }

    public async Task CancelAsync(int bookingId, int customerUserId)
    {
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        p.Add("@BookingID", bookingId, DbType.Int32);
        p.Add("@CustomerUserID", customerUserId, DbType.Int32);

        await conn.ExecuteAsync("sp_CancelBooking", p, commandType: CommandType.StoredProcedure);
    }

    public async Task ApplyPromotionAsync(int bookingId, int customerUserId, string discountCode)
    {
        using var conn = await _factory.OpenAsync();

        // Lookup promotion ID and discount code ID
        var sqlLookup = @"
            SELECT dc.DiscountCodeID, dc.PromotionID
            FROM DiscountCode dc
            JOIN Promotion p ON p.PromotionID = dc.PromotionID
            WHERE dc.CodeValue = @DiscountCode
              AND dc.CodeStatus = 'Active'
              AND p.PromotionStatus = 'Active'
              AND p.ConcertID = (SELECT ConcertID FROM Booking WHERE BookingID = @BookingID AND CustomerUserID = @CustomerUserID)";
              
        var codeInfo = await conn.QuerySingleOrDefaultAsync<dynamic>(sqlLookup, 
            new { DiscountCode = discountCode, BookingID = bookingId, CustomerUserID = customerUserId });

        if (codeInfo == null)
            throw new ArgumentException("Mã giảm giá không hợp lệ hoặc không áp dụng cho booking này.");

        var p = new DynamicParameters();
        p.Add("@BookingID",    bookingId,    DbType.Int32);
        p.Add("@PromotionID", (int)codeInfo.PromotionID, DbType.Int32);
        p.Add("@DiscountCodeID", (int)codeInfo.DiscountCodeID, DbType.Int32);
        p.Add("@ActorUserID", customerUserId, DbType.Int32);

        await conn.ExecuteAsync("sp_ApplyPromotion", p,
            commandType: CommandType.StoredProcedure);
    }
}