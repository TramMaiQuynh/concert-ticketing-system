using System.Data;
using Dapper;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.DTOs;

using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.Infrastructure.Repositories;



public class CheckInRepository : ICheckInRepository
{
    private readonly IDbConnectionFactory _factory;

    public CheckInRepository(IDbConnectionFactory factory)
    {
        _factory = factory;
    }

    public async Task<CheckInResponse> CheckInAsync(int staffUserId, CheckInRequest request)
    {
        using var conn = await _factory.OpenAsync();

        var p = new DynamicParameters();
        // size 64 = đúng độ rộng của @TicketCode VARCHAR(64) trong sp_CheckInTicket và của
        // cột Ticket.TicketCode. Khai báo rộng hơn (trước đây 100) khiến giá trị dài hơn 64
        // bị SQL Server cắt cụt lặng lẽ ở biên tham số — một mã vé sai có thể trở thành
        // tiền tố khớp với mã khác thay vì bị từ chối.
        // AnsiString khớp kiểu VARCHAR (không phải NVARCHAR) của cột.
        p.Add("@TicketCode",          request.TicketCode,  DbType.AnsiString, size: 64);
        p.Add("@ConcertID",           request.ConcertId,   DbType.Int32);
        p.Add("@CheckInStaffUserID",  staffUserId,         DbType.Int32);
        // @ValidationResult la ma ket qua thuan ASCII ("SUCCESS", "ALREADY_USED"...),
        // khac @ValidationInfo (thong diep NVARCHAR co the co tieng Viet) ngay ben duoi.
        p.Add("@ValidationResult",    dbType: DbType.AnsiString, size: 32,  direction: ParameterDirection.Output);
        p.Add("@ValidationInfo",      dbType: DbType.String, size: 500, direction: ParameterDirection.Output);
        p.Add("@CheckInTimestamp",    dbType: DbType.DateTime2,         direction: ParameterDirection.Output);

        await conn.ExecuteAsync("sp_CheckInTicket", p,
            commandType: CommandType.StoredProcedure);

        var result = p.Get<string>("@ValidationResult");
        var info   = p.Get<string>("@ValidationInfo");

        // Thời điểm check-in phải là giá trị ĐÃ GHI vào CheckIn.CheckInTimestamp, đọc
        // ngược ra từ tham số OUTPUT. Bản trước dùng DateTime.UtcNow — một mốc do tầng
        // ứng dụng tự sinh SAU khi SP chạy xong, nên nhân viên soát vé nhìn thấy một
        // con số không tồn tại trong cơ sở dữ liệu và lệch với bản ghi đúng bằng độ trễ
        // khứ hồi. Đây cũng là mốc duy nhất trong toàn hệ thống đi ra ngoài theo quy ước
        // UTC, trong khi mọi mốc khác đi thẳng từ DB; đọc ngược ra làm nó thống nhất với
        // phần còn lại thay vì là ngoại lệ.
        return new CheckInResponse(
            result,
            info,
            p.Get<DateTime?>("@CheckInTimestamp"));
    }

    public async Task<CheckInPreview?> PreviewAsync(CheckInRequest request)
    {
        using var conn = await _factory.OpenAsync();

        // Chỉ đọc, không gọi sp_CheckInTicket (SP đó luôn ghi nhận một lượt check-in mỗi
        // lần gọi, kể cả khi thất bại). Tên khách đi qua VW_CheckInStaffUserAccount thay vì
        // đọc thẳng UserAccount: view đó đã ẩn PasswordHash và tự giới hạn — qua
        // SESSION_CONTEXT do IDbConnectionFactory set theo JWT của nhân viên đang gọi —
        // chỉ còn thấy khách có vé thuộc Concert mình được phân công (BR39). Nhân viên chưa
        // được phân công cho Concert này sẽ không JOIN được sang view -> trả về null, y hệt
        // vé không tồn tại, không lộ vé đó có tồn tại hay không.
        var sql = @"
            SELECT t.TicketID, t.TicketStatus,
                   s.SeatCode, z.ZoneName, tc.CategoryName,
                   ua.DisplayName, ua.Username
            FROM   Ticket t
            JOIN   EventSeat es      ON es.EventSeatID = t.EventSeatID
            JOIN   Seat s            ON s.SeatID = es.SeatID
            LEFT JOIN Zone z         ON z.ZoneID = s.ZoneID
            JOIN   TicketCategory tc ON tc.ConcertID = es.ConcertID
                                    AND tc.TicketCategoryID = es.TicketCategoryID
            JOIN   Booking b         ON b.BookingID = t.BookingID
            JOIN   VW_CheckInStaffUserAccount ua ON ua.UserID = b.CustomerUserID
            WHERE  t.TicketCode = @TicketCode
              AND  t.ConcertID  = @ConcertID;";

        var p = new DynamicParameters();
        p.Add("@TicketCode", request.TicketCode, DbType.AnsiString, size: 64);
        p.Add("@ConcertID",  request.ConcertId,  DbType.Int32);

        return await conn.QuerySingleOrDefaultAsync<CheckInPreview>(sql, p);
    }
}