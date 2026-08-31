using System.Net;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace ConcertTicketing.API.Middleware;

/// <summary>
/// Global exception handler: chuyển đổi exception thành RFC 7807 Problem Details.
/// Bắt toàn bộ SqlException từ Stored Procedures và map sang HTTP status code chuẩn.
/// </summary>
public class ErrorHandlingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<ErrorHandlingMiddleware> _logger;

    public ErrorHandlingMiddleware(RequestDelegate next, ILogger<ErrorHandlingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            await HandleExceptionAsync(context, ex);
        }
    }

    private async Task HandleExceptionAsync(HttpContext context, Exception exception)
    {
        _logger.LogError(exception, "Unhandled exception for {Method} {Path}",
            context.Request.Method, context.Request.Path);

        var (statusCode, title, detail) = exception switch
        {
            SqlException sqlEx => MapSqlException(sqlEx),
            ArgumentException argEx => (HttpStatusCode.BadRequest, "Invalid Argument", argEx.Message),
            UnauthorizedAccessException => (HttpStatusCode.Unauthorized, "Unauthorized", "Bạn không có quyền thực hiện thao tác này."),
            _ => (HttpStatusCode.InternalServerError, "Internal Server Error", "Đã có lỗi xảy ra. Vui lòng thử lại sau.")
        };

        context.Response.StatusCode = (int)statusCode;
        context.Response.ContentType = "application/problem+json";

        var problemDetail = new
        {
            type = "https://api.concert.vn/errors/" + title.ToLower().Replace(" ", "-"),
            title,
            status = (int)statusCode,
            detail,
            instance = context.Request.Path.Value,
            traceId = context.TraceIdentifier
        };

        var json = JsonSerializer.Serialize(problemDetail, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase
        });

        await context.Response.WriteAsync(json);
    }

    private static (HttpStatusCode, string, string) MapSqlException(SqlException ex)
    {
        return ex.Number switch
        {
            // sp_CreateBooking
            51001 => (HttpStatusCode.BadRequest, "Concert Not On Sale", "Concert hiện không trong trạng thái mở bán vé."),
            51002 => (HttpStatusCode.BadRequest, "Empty Seat List", "Danh sách ghế không được để trống."),
            51003 => (HttpStatusCode.UnprocessableEntity, "Purchase Limit Exceeded", "Bạn đã vượt quá giới hạn số vé được mua cho concert này."),
            51004 => (HttpStatusCode.Conflict, "Seat Unavailable", "Một hoặc nhiều ghế bạn chọn đã được người khác đặt. Vui lòng chọn ghế khác."),
            51005 => (HttpStatusCode.BadRequest, "Invalid Waitlist Entry", "Thông tin hàng đợi không hợp lệ."),

            // sp_ConfirmPayment
            52001 => (HttpStatusCode.NotFound, "Booking Not Found", "Booking không tồn tại trong hệ thống."),
            52002 => (HttpStatusCode.Conflict, "Booking Not Pending", "Booking này không ở trạng thái chờ thanh toán."),
            52003 => (HttpStatusCode.Gone, "Booking Expired", "Thời gian giữ chỗ đã hết hạn. Vui lòng đặt lại."),
            52005 => (HttpStatusCode.BadRequest, "Payment Amount Mismatch", "Số tiền thanh toán không khớp với tổng hóa đơn."),

            // sp_ProcessRefund
            53001 => (HttpStatusCode.NotFound, "Payment Not Found", "Thông tin thanh toán không tồn tại."),
            53004 => (HttpStatusCode.UnprocessableEntity, "Refund Exceeds Payment", "Số tiền hoàn trả vượt quá số tiền đã thanh toán."),
            53005 => (HttpStatusCode.Forbidden, "Refund Not Authorized", "Bạn không có quyền hoàn tiền cho Payment này."),

            // sp_ApplyPromotion
            54006 => (HttpStatusCode.BadRequest, "Promotion Expired", "Mã khuyến mãi đã hết hiệu lực."),
            54009 => (HttpStatusCode.BadRequest, "Invalid Discount Code", "Mã khuyến mãi không hợp lệ."),

            // sp_CancelBooking
            55001 => (HttpStatusCode.NotFound, "Booking Not Found", "Booking không tồn tại hoặc không thuộc quyền sở hữu của bạn."),
            55002 => (HttpStatusCode.Conflict, "Booking Not Pending", "Chỉ có thể hủy Booking đang ở trạng thái chờ thanh toán."),

            // sp_InitiatePayment
            56001 => (HttpStatusCode.NotFound, "Booking Not Found", "Booking không tồn tại hoặc không thuộc quyền sở hữu của bạn."),
            56002 => (HttpStatusCode.Conflict, "Booking Not Pending", "Chỉ có thể thanh toán cho Booking đang ở trạng thái chờ."),
            56003 => (HttpStatusCode.Conflict, "Payment Already Pending", "Đã có giao dịch thanh toán đang chờ xử lý cho Booking này."),

            // sp_RegisterUser
            57001 => (HttpStatusCode.Conflict, "Username Exists", "Tên đăng nhập này đã có người sử dụng. Vui lòng chọn tên khác."),
            57002 => (HttpStatusCode.InternalServerError, "Role Not Found", "Lỗi hệ thống: Role Customer không tồn tại hoặc không hoạt động."),

            // sp_CreateConcert / sp_UpdateConcert / sp_UpdateConcertStatus
            58001 => (HttpStatusCode.BadRequest, "Invalid Concert Status", "ConcertStatus không hợp lệ."),
            58002 => (HttpStatusCode.BadRequest, "Invalid Concert Dates", "EndDatetime phải sau StartDatetime."),
            58003 => (HttpStatusCode.BadRequest, "Invalid Purchase Limit", "PurchaseLimit phải lớn hơn 0."),
            58004 => (HttpStatusCode.BadRequest, "Artist Not Found", "Nghệ sĩ không tồn tại."),
            58005 => (HttpStatusCode.BadRequest, "Venue Not Found", "Địa điểm không tồn tại."),
            58006 => (HttpStatusCode.BadRequest, "Organizer Not Found", "Organizer không tồn tại hoặc không hoạt động."),
            58010 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58011 => (HttpStatusCode.Conflict, "Concert Not Editable", "Chỉ sửa được Concert ở trạng thái Draft hoặc Published."),
            58012 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền cập nhật Concert này."),
            58013 => (HttpStatusCode.BadRequest, "Invalid Concert Dates", "EndDatetime phải sau StartDatetime."),
            58020 => (HttpStatusCode.BadRequest, "Invalid Concert Status", "ConcertStatus không hợp lệ."),
            58021 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58022 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền."),

            // sp_CreateVenue / sp_CreateZone / sp_CreateSeat
            58101 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin được thực hiện thao tác này."),
            58102 => (HttpStatusCode.BadRequest, "Invalid Venue Name", "Tên Venue không được để trống."),
            58111 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin được tạo Zone."),
            58112 => (HttpStatusCode.BadRequest, "Venue Not Found", "Venue không tồn tại."),
            58113 => (HttpStatusCode.BadRequest, "Invalid Zone Code", "ZoneCode không được để trống."),
            58121 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin được tạo Seat."),
            58122 => (HttpStatusCode.BadRequest, "Zone Not Found", "Zone không tồn tại."),
            58123 => (HttpStatusCode.BadRequest, "Invalid Seat Code", "SeatCode không được để trống."),

            // sp_ConfigureTicketCategory / sp_AddEventSeats
            58201 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58202 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền."),
            58203 => (HttpStatusCode.BadRequest, "Invalid Category Name", "CategoryName không được để trống."),
            58211 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58212 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền."),
            58213 => (HttpStatusCode.BadRequest, "Category Not Found", "TicketCategory không thuộc Concert hoặc không Active."),
            58214 => (HttpStatusCode.BadRequest, "Invalid Price", "SalePrice không được âm."),
            58215 => (HttpStatusCode.BadRequest, "Empty Seat List", "Danh sách ghế không được trống."),
            58216 => (HttpStatusCode.BadRequest, "Seat Not Found", "Có Seat không tồn tại."),
            58217 => (HttpStatusCode.Conflict, "Seat Already In Inventory", "Có Seat đã có trong kho vé của Concert."),

            // sp_CreatePromotion
            58301 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58302 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền."),
            58303 => (HttpStatusCode.BadRequest, "Invalid Discount Type", "DiscountType phải là PERCENTAGE hoặc FIXED."),
            58304 => (HttpStatusCode.BadRequest, "Invalid Discount Value", "DiscountValue phải lớn hơn 0."),
            58305 => (HttpStatusCode.BadRequest, "Invalid Promotion Dates", "EndDatetime phải sau StartDatetime."),

            // sp_AssignRole
            58401 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin được gán/thu hồi Role."),
            58402 => (HttpStatusCode.BadRequest, "User Not Found", "User không tồn tại."),
            58403 => (HttpStatusCode.BadRequest, "Role Not Found", "Role không tồn tại hoặc không Active."),
            58404 => (HttpStatusCode.Forbidden, "System Account Protected", "Không được gán Role cho tài khoản hệ thống."),

            // sp_JoinWaitlist
            58501 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58502 => (HttpStatusCode.Conflict, "Waitlist Disabled", "Concert không bật Waitlist."),
            58503 => (HttpStatusCode.Conflict, "Already In Waitlist", "Bạn đã có entry đang hoạt động cho Concert này."),

            // sp_CreateDiscountCode (BP13 / FR52)
            58601 => (HttpStatusCode.Forbidden, "Promotion Not Authorized", "Bạn không có quyền với Promotion này."),
            58602 => (HttpStatusCode.BadRequest, "Invalid Discount Code", "CodeValue không được để trống."),
            58603 => (HttpStatusCode.BadRequest, "Invalid Discount Code Dates", "ValidToDatetime phải sau ValidFromDatetime."),

            // sp_JoinQueue (BP11 / FR64)
            58701 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58702 => (HttpStatusCode.Conflict, "Fair Access Disabled", "Concert không bật Fair Access."),
            58703 => (HttpStatusCode.Conflict, "Already In Queue", "Bạn đã có entry đang hoạt động trong Queue này."),

            // sp_SetEventSeatUnavailable (BP3 / BR08)
            58801 => (HttpStatusCode.NotFound, "EventSeat Not Found", "EventSeat không tồn tại."),
            58802 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền."),
            58803 => (HttpStatusCode.BadRequest, "Invalid EventSeat Status", "Chỉ thay đổi được khi trạng thái Available hoặc Unavailable."),
            58804 => (HttpStatusCode.BadRequest, "Reason Required", "Phải cung cấp Reason khi đánh dấu Unavailable."),

            // sp_AdminUpdateUserStatus (BP12 / BR52)
            58901 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin thực hiện thao tác này."),
            58902 => (HttpStatusCode.BadRequest, "Invalid User Status", "UserStatus không hợp lệ."),
            58903 => (HttpStatusCode.NotFound, "User Not Found", "User không tồn tại."),
            58904 => (HttpStatusCode.Forbidden, "System Account Protected", "Không thay đổi trạng thái tài khoản hệ thống."),

            // sp_AddCheckinStaffAssignment (BP9 / BR39 / FR51)
            59001 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin thực hiện thao tác này."),
            59002 => (HttpStatusCode.NotFound, "Staff Not Found", "Staff không tồn tại."),
            59003 => (HttpStatusCode.BadRequest, "Staff Role Missing", "User không có role Check-in Staff."),
            59004 => (HttpStatusCode.BadRequest, "Empty Concert List", "Danh sách Concert không được trống."),

            // State Machine (BR49) — TRG_*_StateTransition: chuyển trạng thái không hợp lệ
            50001 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái Concert không hợp lệ."),
            50002 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái Booking không hợp lệ."),
            50003 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái Payment không hợp lệ."),
            50004 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái Ticket không hợp lệ."),
            50005 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái EventSeat không hợp lệ."),
            50006 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái Refund không hợp lệ."),
            50007 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái WaitlistEntry không hợp lệ."),
            50008 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái QueueEntry không hợp lệ."),
            50009 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái Waitlist không hợp lệ."),
            50010 => (HttpStatusCode.Conflict, "Invalid State Transition", "Chuyển trạng thái Queue không hợp lệ."),

            // Duplicate Key
            2627 => (HttpStatusCode.Conflict, "Duplicate Entry", "Bản ghi đã tồn tại."),

            _ => (HttpStatusCode.InternalServerError, "Database Error", "Đã xảy ra lỗi cơ sở dữ liệu (Code: " + ex.Number + ").")
        };
    }
}
