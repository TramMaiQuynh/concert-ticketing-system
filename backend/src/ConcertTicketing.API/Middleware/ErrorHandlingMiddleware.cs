using System.Net;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using ConcertTicketing.Application.Services;

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
            // Phải đứng TRƯỚC nhánh UnauthorizedAccessException chung bên dưới: switch khớp
            // theo thứ tự khai báo, và InvalidCredentialsException LÀ MỘT UnauthorizedAccessException
            // (kế thừa) nên nhánh chung phía sau sẽ khớp trước nếu đổi chỗ, nuốt mất Message
            // đã được AuthService cân nhắc kỹ cho riêng lỗi đăng nhập.
            InvalidCredentialsException credEx => (HttpStatusCode.Unauthorized, "Unauthorized", credEx.Message),
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
            51006 => (HttpStatusCode.Conflict, "Concurrent Booking Request",
                      "Hệ thống đang xử lý một yêu cầu đặt vé khác của bạn cho concert này. Vui lòng thử lại."),

            // sp_ConfirmPayment
            52001 => (HttpStatusCode.NotFound, "Booking Not Found", "Booking không tồn tại trong hệ thống."),
            52002 => (HttpStatusCode.Conflict, "Booking Not Pending", "Booking này không ở trạng thái chờ thanh toán."),
            // 52005 (Payment Amount Mismatch) đã bị gỡ: sp_ConfirmPayment không còn ném
            // lỗi cho trường hợp lệch số tiền. Ném lỗi ở đó đồng nghĩa với ROLLBACK bản
            // ghi "tiền đã thu" — nay nhánh này tạo Refund và trả về thành công cho cổng
            // thanh toán, đúng với hai nhánh bất thường còn lại của cùng SP.

            52006 => (HttpStatusCode.Conflict, "Payment In Progress", "Hệ thống đang xử lý yêu cầu cho Booking này. Vui lòng thử lại."),
            // 52003 (Booking Expired) và 52004 (Payment Already Confirmed) đã được gỡ:
            // sp_ConfirmPayment không còn ném hai mã này. Booking hết hạn nay đi theo
            // nhánh tự hoàn tiền (BR22a/LI02a) và callback lặp thì trả về sớm — cả hai
            // đều KHÔNG phải lỗi, nên được báo qua Outcome trong body chứ không qua
            // HTTP status. Giữ mapping cho mã không còn tồn tại chỉ tạo ảo giác về
            // độ phủ khi đối chiếu với tầng DB.

            // sp_ProcessRefund
            53010 => (HttpStatusCode.NotFound, "Booking Not Found", "Booking không tồn tại."),
            53011 => (HttpStatusCode.Forbidden, "Refund Not Authorized", "Bạn không có quyền hoàn tiền cho Booking này."),
            53012 => (HttpStatusCode.UnprocessableEntity, "Payment Not Found", "Không tìm thấy giao dịch thanh toán hợp lệ của Booking đã xác nhận."),
            53013 => (HttpStatusCode.UnprocessableEntity, "Cancellation Deadline Passed", "Đã quá hạn hủy vé hoặc Concert không cho phép hủy."),
            53015 => (HttpStatusCode.Conflict, "Booking Not Cancellable", "Chỉ hủy được Booking đang ở trạng thái chờ hoặc đã xác nhận."),
            53016 => (HttpStatusCode.Forbidden, "Concert Cancellation Restricted", "Chỉ Organizer hoặc Admin được hủy theo diện hủy Concert."),

            // sp_ConfirmRefund
            53101 => (HttpStatusCode.NotFound, "Refund Not Found", "Yêu cầu hoàn tiền không tồn tại."),
            53102 => (HttpStatusCode.Conflict, "Refund Not Pending", "Yêu cầu hoàn tiền không ở trạng thái chờ xử lý."),
            53103 => (HttpStatusCode.Forbidden, "Refund Not Authorized", "Bạn không có quyền xác nhận hoàn tiền này."),

            // sp_ApplyPromotion
            54001 => (HttpStatusCode.NotFound, "Booking Not Found", "Booking không tồn tại."),
            54002 => (HttpStatusCode.Conflict, "Booking Not Pending", "Chỉ áp dụng khuyến mãi cho Booking đang chờ thanh toán."),
            54003 => (HttpStatusCode.NotFound, "Promotion Not Found", "Chương trình khuyến mãi không tồn tại."),
            54004 => (HttpStatusCode.BadRequest, "Promotion Concert Mismatch", "Khuyến mãi không áp dụng cho Concert của Booking này."),
            54005 => (HttpStatusCode.BadRequest, "Promotion Not Active", "Chương trình khuyến mãi hiện không được phát hành."),
            54006 => (HttpStatusCode.BadRequest, "Promotion Expired", "Mã khuyến mãi đã hết hiệu lực."),
            54007 => (HttpStatusCode.UnprocessableEntity, "Promotion Exhausted", "Chương trình khuyến mãi đã đạt giới hạn số lượt sử dụng."),
            54008 => (HttpStatusCode.BadRequest, "Discount Code Required", "Khuyến mãi này bắt buộc phải kèm mã giảm giá."),
            54009 => (HttpStatusCode.BadRequest, "Invalid Discount Code", "Mã khuyến mãi không hợp lệ."),
            54010 => (HttpStatusCode.Conflict, "Promotion Already Applied", "Khuyến mãi này đã được áp dụng cho Booking."),
            54011 => (HttpStatusCode.UnprocessableEntity, "Discount Code Exhausted", "Mã giảm giá đã đạt giới hạn sử dụng."),
            54012 => (HttpStatusCode.UnprocessableEntity, "Discount Code Limit Per Customer", "Bạn đã dùng hết lượt cho phép của mã giảm giá này."),

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
            58002 => (HttpStatusCode.BadRequest, "Invalid Concert Dates", "EndDatetime phải sau StartDatetime."),
            58003 => (HttpStatusCode.BadRequest, "Invalid Purchase Limit", "PurchaseLimit phải lớn hơn 0."),
            58004 => (HttpStatusCode.BadRequest, "Artist Not Found", "Nghệ sĩ không tồn tại."),
            58005 => (HttpStatusCode.BadRequest, "Venue Not Found", "Địa điểm không tồn tại."),
            58007 => (HttpStatusCode.BadRequest, "Invalid Sale Window", "SaleEndDatetime phải sau hoặc bằng SaleStartDatetime."),
            58006 => (HttpStatusCode.BadRequest, "Organizer Not Found", "Organizer không tồn tại hoặc không hoạt động."),
            58010 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58011 => (HttpStatusCode.Conflict, "Concert Not Editable", "Chỉ sửa được Concert ở trạng thái Draft hoặc Published."),
            58012 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền cập nhật Concert này."),
            58013 => (HttpStatusCode.BadRequest, "Invalid Concert Dates", "EndDatetime phải sau StartDatetime."),
            58020 => (HttpStatusCode.BadRequest, "Invalid Concert Status", "ConcertStatus không hợp lệ."),
            58021 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58023 => (HttpStatusCode.UnprocessableEntity, "Inventory Required",
                      "Chưa thể mở bán: Concert chưa có kho vé (EventSeat) nào."),
            58024 => (HttpStatusCode.UnprocessableEntity, "Sale Window Required",
                      "Chưa thể mở bán: Concert chưa cấu hình thời gian bắt đầu/kết thúc bán vé."),
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
            58204 => (HttpStatusCode.NotFound, "Ticket Category Not Found",
                      "Hạng vé không tồn tại hoặc không thuộc Concert này."),
            58203 => (HttpStatusCode.BadRequest, "Invalid Category Name", "CategoryName không được để trống."),
            58211 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58212 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền."),
            58213 => (HttpStatusCode.BadRequest, "Category Not Found", "TicketCategory không thuộc Concert hoặc không Active."),
            58215 => (HttpStatusCode.BadRequest, "Empty Seat List", "Danh sách ghế không được trống."),
            58216 => (HttpStatusCode.BadRequest, "Seat Not Found", "Có Seat không tồn tại."),
            58217 => (HttpStatusCode.Conflict, "Seat Already In Inventory", "Có Seat đã có trong kho vé của Concert."),
            58205 => (HttpStatusCode.BadRequest, "Invalid Base Price", "BasePrice không được âm."),
            58206 => (HttpStatusCode.Conflict, "Concert Not Configurable", "Chỉ cấu hình hạng vé khi Concert ở trạng thái Draft hoặc Published."),
            58218 => (HttpStatusCode.Conflict, "Concert Not Configurable", "Chỉ thêm ghế vào kho vé khi Concert ở trạng thái Draft hoặc Published."),
            58219 => (HttpStatusCode.BadRequest, "Seat Retired", "Có Seat hoặc Zone đã ngừng sử dụng, không thể đưa vào kho vé."),

            // sp_CreatePromotion
            58301 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58302 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền."),
            58303 => (HttpStatusCode.BadRequest, "Invalid Discount Type", "DiscountType phải là 'Percentage' hoặc 'Fixed Amount'."),
            58304 => (HttpStatusCode.BadRequest, "Invalid Discount Value", "DiscountValue phải lớn hơn 0."),
            58306 => (HttpStatusCode.BadRequest, "Promotion Name Required",
                      "Tên chương trình khuyến mãi là bắt buộc khi yêu cầu mã giảm giá."),
            58305 => (HttpStatusCode.BadRequest, "Invalid Promotion Dates", "EndDatetime phải sau StartDatetime."),

            // sp_AssignRole
            58401 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin được gán/thu hồi Role."),
            58402 => (HttpStatusCode.BadRequest, "User Not Found", "User không tồn tại."),
            58403 => (HttpStatusCode.BadRequest, "Role Not Found", "Role không tồn tại hoặc không Active."),
            58404 => (HttpStatusCode.Forbidden, "System Account Protected", "Không được gán Role cho tài khoản hệ thống."),
            58405 => (HttpStatusCode.BadRequest, "Invalid Grant Action", "GrantOrRevoke phải là Grant hoặc Revoke."),
            58406 => (HttpStatusCode.Conflict, "Last Admin Protected", "Không thể thu hồi Role Admin của Admin đang hoạt động cuối cùng."),

            // sp_JoinWaitlist
            58501 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58502 => (HttpStatusCode.Conflict, "Waitlist Disabled", "Concert không bật Waitlist."),
            58503 => (HttpStatusCode.Conflict, "Already In Waitlist", "Bạn đã có entry đang hoạt động cho Concert này."),
            58504 => (HttpStatusCode.BadRequest, "Invalid Requested Quantity", "Số lượng ghế mong muốn phải lớn hơn 0."),
            58505 => (HttpStatusCode.BadRequest, "Category Not Found", "Hạng vé không hợp lệ cho Concert này."),
            58506 => (HttpStatusCode.UnprocessableEntity, "Requested Quantity Exceeds Limit", "Số lượng ghế mong muốn vượt quá giới hạn mua của Concert."),

            // sp_CreateDiscountCode (BP13 / FR52)
            58601 => (HttpStatusCode.Forbidden, "Promotion Not Authorized", "Bạn không có quyền với Promotion này."),
            58602 => (HttpStatusCode.BadRequest, "Invalid Discount Code", "CodeValue không được để trống."),
            58603 => (HttpStatusCode.BadRequest, "Invalid Discount Code Dates", "ValidToDatetime phải sau ValidFromDatetime."),

            // sp_JoinQueue (BP11 / FR64)
            58701 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            58702 => (HttpStatusCode.Conflict, "Fair Access Disabled", "Concert không bật Fair Access."),
            58703 => (HttpStatusCode.Conflict, "Already In Queue", "Bạn đã có entry đang hoạt động trong Queue này."),
            58704 => (HttpStatusCode.Conflict, "Concert Not In Sale Phase", "Chỉ tham gia hàng đợi khi Concert đang mở bán hoặc sắp mở bán."),

            // sp_ExitQueue (BP11 / BR48)
            59201 => (HttpStatusCode.NotFound, "Queue Entry Not Found", "Entry hàng đợi không tồn tại."),
            59202 => (HttpStatusCode.Forbidden, "Queue Exit Not Authorized", "Bạn không có quyền rời hàng đợi này."),
            59203 => (HttpStatusCode.Conflict, "Queue Entry Not Active", "Chỉ rời hàng đợi khi đang chờ hoặc đã được vào."),

            // sp_ApplyPromotion — khóa giá khi đang có giao dịch thanh toán chờ xử lý
            54013 => (HttpStatusCode.Conflict, "Payment In Progress",
                      "Booking đang có giao dịch thanh toán chờ xử lý. Hủy giao dịch đó trước khi thay đổi khuyến mãi."),

            // sp_CreateBooking — Fair Access gate (BR46/BR47)
            51007 => (HttpStatusCode.Forbidden, "Queue Admission Required",
                      "Concert đang áp dụng Fair Access. Bạn cần được vào từ hàng đợi (và còn hạn) trước khi đặt vé."),

            // sp_CreateConcert — ủy quyền theo Actor
            58008 => (HttpStatusCode.Forbidden, "Concert Creation Not Authorized",
                      "Bạn không có quyền tạo Concert cho Organizer này."),

            // sp_ConfigureTicketCategory — trạng thái hạng vé (FR12)
            58207 => (HttpStatusCode.BadRequest, "Invalid Category Status", "CategoryStatus phải là Active hoặc Inactive."),
            58208 => (HttpStatusCode.Conflict, "Category In Use",
                      "Không thể ngừng bán hạng vé khi còn ghế đang được giữ hoặc đã bán."),

            // sp_JoinQueue / sp_JoinWaitlist — tạo hàng đợi
            58507 => (HttpStatusCode.Conflict, "Waitlist Closed", "Waitlist của Concert này đang đóng."),
            58705 => (HttpStatusCode.InternalServerError, "Missing Configuration",
                      "Thiếu cấu hình nền Queue_Default_Admission_Capacity."),
            58706 => (HttpStatusCode.Conflict, "Queue Closed", "Queue của Concert này đang đóng."),

            // sp_AddCheckinStaffAssignment (BR39 / FR51)
            59005 => (HttpStatusCode.BadRequest, "Invalid Assignment Status", "AssignmentStatus phải là Active hoặc Revoked."),

            // sp_ProcessQueueAdmission (BR47b)
            59301 => (HttpStatusCode.InternalServerError, "Missing Configuration",
                      "Thiếu booking_ttl: đặt Queue.AdmissionValiditySeconds hoặc cấu hình nền Queue_Admission_Validity."),

            // sp_UpdateRefundStatus (§10.1 / §24.4 / BR32) — kết thúc yêu cầu hoàn
            // tiền mà không chi trả. Không đụng tới Payment.
            59911 => (HttpStatusCode.BadRequest, "Invalid Refund Status",
                      "Status phải là Failed hoặc Cancelled. Muốn xác nhận đã hoàn tiền xong thì dùng refunds/{id}/confirm."),
            59912 => (HttpStatusCode.BadRequest, "Refund Reason Required",
                      "Phải ghi lý do — đây là thao tác đóng một yêu cầu hoàn tiền mà khách không nhận được tiền."),
            59913 => (HttpStatusCode.NotFound, "Refund Not Found", "Khoản hoàn tiền không tồn tại."),
            59914 => (HttpStatusCode.Conflict, "Refund Not Pending",
                      "Chỉ kết thúc được khoản hoàn đang chờ xử lý (Pending)."),
            59915 => (HttpStatusCode.Forbidden, "Refund Actor Forbidden",
                      "Chỉ Admin hoặc Organizer sở hữu Concert được thực hiện thao tác này."),

            // sp_UpdateRoleStatus (§12.3.2 / §24.4 / BR52) — mở/đóng khả năng PHÂN CÔNG
            // của một vai trò. Không tác động tới người đang giữ vai trò.
            59901 => (HttpStatusCode.Forbidden, "Admin Only", "Chỉ Admin được đổi trạng thái Role."),
            59902 => (HttpStatusCode.NotFound, "Role Not Found", "Role không tồn tại."),
            59903 => (HttpStatusCode.BadRequest, "Invalid Role Status", "RoleStatus phải là Active hoặc Inactive."),
            59904 => (HttpStatusCode.Conflict, "System Role Protected",
                      "Không thể ngừng phân công Role Customer hoặc Admin — hệ thống phụ thuộc vào chúng "
                      + "để đăng ký tài khoản và để luôn còn quản trị viên."),

            // sp_UpdateVenue / sp_UpdateZone / sp_UpdateSeat (FR59b / BR50e)
            59401 => (HttpStatusCode.Forbidden, "Admin Only", "Chỉ Admin được cập nhật Venue."),
            59402 => (HttpStatusCode.NotFound, "Venue Not Found", "Venue không tồn tại."),
            59403 => (HttpStatusCode.BadRequest, "Invalid Venue Status", "VenueStatus phải là Active hoặc Inactive."),
            59404 => (HttpStatusCode.BadRequest, "Venue Name Required", "VenueName không được để trống."),
            59405 => (HttpStatusCode.Conflict, "Venue In Use",
                      "Không thể ngừng sử dụng Venue đang được Concert chưa kết thúc tham chiếu."),
            59411 => (HttpStatusCode.Forbidden, "Admin Only", "Chỉ Admin được cập nhật Zone."),
            59412 => (HttpStatusCode.NotFound, "Zone Not Found", "Zone không tồn tại."),
            59413 => (HttpStatusCode.BadRequest, "Invalid Zone Status", "ZoneStatus phải là Active hoặc Retired."),
            59415 => (HttpStatusCode.Conflict, "Zone In Use",
                      "Không thể Retire Zone đang có ghế trong kho vé của Concert chưa kết thúc."),
            59421 => (HttpStatusCode.Forbidden, "Admin Only", "Chỉ Admin được cập nhật Seat."),
            59422 => (HttpStatusCode.NotFound, "Seat Not Found", "Seat không tồn tại."),
            59423 => (HttpStatusCode.BadRequest, "Invalid Seat Status", "SeatStatus phải là Active hoặc Retired."),
            59425 => (HttpStatusCode.Conflict, "Seat In Use",
                      "Không thể Retire Seat đang nằm trong kho vé của Concert chưa kết thúc."),

            // sp_ConfigureQueue / sp_ConfigureWaitlist (FR64a, BR43, BR45b, BR47b)
            59501 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            59502 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền cấu hình Concert này."),
            59503 => (HttpStatusCode.BadRequest, "Invalid Queue Policy", "FairAccessPolicy phải là FIFO hoặc RANDOM."),
            59504 => (HttpStatusCode.BadRequest, "Invalid Admission Capacity", "AdmissionCapacity phải lớn hơn 0."),
            59505 => (HttpStatusCode.BadRequest, "Invalid Booking TTL", "AdmissionValiditySeconds phải lớn hơn 0."),
            59506 => (HttpStatusCode.BadRequest, "Invalid Queue Status", "QueueStatus phải là Open hoặc Closed."),
            59507 => (HttpStatusCode.Conflict, "Fair Access Disabled",
                      "Không thể mở Queue khi Concert chưa bật FairAccessEnabled."),
            59511 => (HttpStatusCode.NotFound, "Concert Not Found", "Concert không tồn tại."),
            59512 => (HttpStatusCode.Forbidden, "Concert Not Authorized", "Bạn không có quyền cấu hình Concert này."),
            59513 => (HttpStatusCode.BadRequest, "Invalid Waitlist Policy", "AllocationPolicy phải là FIFO hoặc RANDOM."),
            59514 => (HttpStatusCode.BadRequest, "Invalid Waitlist Status", "WaitlistStatus phải là Open hoặc Closed."),
            59515 => (HttpStatusCode.Conflict, "Waitlist Disabled",
                      "Không thể mở Waitlist khi Concert chưa bật WaitlistEnabled."),

            // ── Sơ đồ chỗ ngồi: hình học địa điểm / khu / ghế (FR11a) ─────────
            // sp_ConfigureVenueMap
            59801 => (HttpStatusCode.Forbidden, "Venue Map Not Authorized",
                      "Chỉ Admin được cấu hình sơ đồ địa điểm."),
            59802 => (HttpStatusCode.NotFound, "Venue Not Found", "Địa điểm không tồn tại."),
            59803 => (HttpStatusCode.BadRequest, "Invalid Map Size",
                      "Kích thước mặt phẳng và sân khấu phải lớn hơn 0."),
            59804 => (HttpStatusCode.Conflict, "Map Too Small",
                      "Mặt phẳng mới nhỏ hơn vùng các khu đang chiếm. Đặt lại vị trí các khu trước."),
            59805 => (HttpStatusCode.BadRequest, "Incomplete Stage",
                      "Sân khấu phải có đủ X, Y, Width, Height."),
            59806 => (HttpStatusCode.Conflict, "Map Not Configured",
                      "Phải khai báo mặt phẳng trước khi đặt sân khấu."),
            59807 => (HttpStatusCode.UnprocessableEntity, "Stage Outside Map",
                      "Sân khấu phải nằm trọn trong mặt phẳng của địa điểm."),

            // sp_CreateZone / sp_UpdateZone — hình học khu
            59811 => (HttpStatusCode.BadRequest, "Invalid Zone Type",
                      "ZoneType phải là 'Seated' hoặc 'GeneralAdmission'."),
            59812 => (HttpStatusCode.BadRequest, "Incomplete Zone Box",
                      "Vị trí khu phải có đủ X, Y, Width, Height."),
            59813 => (HttpStatusCode.BadRequest, "Invalid Zone Size",
                      "Kích thước khu phải lớn hơn 0."),
            59814 => (HttpStatusCode.Conflict, "Venue Map Not Configured",
                      "Chưa cấu hình sơ đồ địa điểm. Khai báo mặt phẳng trước khi đặt vị trí khu."),
            59815 => (HttpStatusCode.UnprocessableEntity, "Zone Outside Map",
                      "Khu nằm ngoài mặt phẳng của địa điểm."),
            59816 => (HttpStatusCode.BadRequest, "Invalid Zone Rotation",
                      "Góc xoay phải trong khoảng -360 đến 360 độ."),
            59817 => (HttpStatusCode.BadRequest, "Missing Zone Capacity",
                      "Khu vé đứng phải khai báo sức chứa lớn hơn 0."),
            59818 => (HttpStatusCode.BadRequest, "Capacity Not Applicable",
                      "Chỉ khu vé đứng mới có sức chứa; khu có ghế thì sức chứa do số ghế quyết định."),
            59819 => (HttpStatusCode.Conflict, "Zone Has Seats",
                      "Không thể chuyển sang khu vé đứng khi khu đang có ghế."),

            // sp_CreateSeat / sp_UpdateSeat — vị trí ghế
            59821 => (HttpStatusCode.BadRequest, "Incomplete Seat Position",
                      "Hàng và số thứ tự trong hàng phải đi cùng nhau."),
            59822 => (HttpStatusCode.BadRequest, "Invalid Seat Column",
                      "Số thứ tự trong hàng phải lớn hơn 0."),
            59823 => (HttpStatusCode.Conflict, "Seat In General Admission Zone",
                      "Không gán được vị trí ghế cho khu vé đứng."),
            59824 => (HttpStatusCode.Conflict, "Seat Position Taken",
                      "Vị trí này trong khu đã có ghế khác."),

            // sp_UpdatePromotionStatus / sp_UpdateDiscountCodeStatus (FR52, FR53b)
            59601 => (HttpStatusCode.BadRequest, "Invalid Promotion Status", "PromotionStatus phải là Draft, Active hoặc Disabled."),
            59602 => (HttpStatusCode.NotFound, "Promotion Not Found", "Promotion không tồn tại."),
            59603 => (HttpStatusCode.Forbidden, "Promotion Not Authorized", "Bạn không có quyền với Promotion này."),
            59604 => (HttpStatusCode.Conflict, "Promotion Already Published",
                      "Không thể đưa Promotion đã công bố trở lại Draft — dùng Disabled để ngừng phát hành."),
            59611 => (HttpStatusCode.BadRequest, "Invalid Code Status", "CodeStatus phải là Active hoặc Disabled."),
            59612 => (HttpStatusCode.NotFound, "Discount Code Not Found", "Mã giảm giá không tồn tại."),
            59613 => (HttpStatusCode.Forbidden, "Discount Code Not Authorized", "Bạn không có quyền với mã giảm giá này."),

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
            58905 => (HttpStatusCode.Forbidden, "Self Lock Forbidden", "Admin không được tự khóa hoặc vô hiệu hóa chính mình."),
            58906 => (HttpStatusCode.Conflict, "Last Admin Protected", "Không thể khóa Admin đang hoạt động cuối cùng của hệ thống."),

            // sp_CreateArtist / sp_UpdateArtist (BP1 / FR03 / BR50e)
            59101 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin được tạo Artist."),
            59102 => (HttpStatusCode.BadRequest, "Invalid Artist Name", "Tên nghệ sĩ không được để trống."),
            59111 => (HttpStatusCode.Forbidden, "Admin Required", "Chỉ Admin được cập nhật Artist."),
            59112 => (HttpStatusCode.NotFound, "Artist Not Found", "Nghệ sĩ không tồn tại."),
            59113 => (HttpStatusCode.BadRequest, "Invalid Artist Status", "ArtistStatus phải là Active hoặc Retired."),
            59114 => (HttpStatusCode.BadRequest, "Invalid Artist Name", "Tên nghệ sĩ không được để trống."),
            59115 => (HttpStatusCode.Conflict, "Artist In Use", "Không thể ngừng sử dụng nghệ sĩ đang gắn với Concert chưa kết thúc."),

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

            // Trigger bất biến / integrity (§23.4)
            50000 => (HttpStatusCode.Conflict, "Allocation Concert Mismatch", "Ghế được phân bổ không thuộc Concert của Booking."),
            50011 => (HttpStatusCode.UnprocessableEntity, "Concert Not Publishable", "Concert chưa đủ thông tin bắt buộc để công bố (Organizer, Artist, Venue, thời gian)."),
            50012 => (HttpStatusCode.Conflict, "Ticket Concert Mismatch", "Vé không thuộc Concert của Booking."),
            50013 => (HttpStatusCode.Conflict, "CheckIn Concert Mismatch", "Check-in không thuộc Concert của vé."),
            50015 => (HttpStatusCode.Conflict, "Seat Status Locked", "Không thể mở lại ghế khi Concert đã đóng bán, kết thúc hoặc bị hủy."),
            50016 => (HttpStatusCode.BadRequest, "Waitlist Category Mismatch", "Hạng vé không thuộc cùng Concert với danh sách chờ."),
            50017 => (HttpStatusCode.BadRequest, "Waitlist Seat Mismatch", "Ghế được cấp không đúng Concert hoặc hạng vé đã đăng ký."),
            50020 => (HttpStatusCode.BadRequest, "Seat Venue Mismatch", "Ghế không thuộc địa điểm của Concert."),
            50030 or 50031 => (HttpStatusCode.Conflict, "Allocation Inconsistent", "Trạng thái ghế không nhất quán với phân bổ đang hoạt động."),
            50040 => (HttpStatusCode.Conflict, "Ticket Count Mismatch", "Số vé phát hành không khớp số ghế đã giữ."),
            50050 => (HttpStatusCode.Conflict, "Duplicate Active Ticket", "Ghế này đã có vé đang hiệu lực."),
            50061 => (HttpStatusCode.BadRequest, "Sale Price Mismatch", "Giá bán của ghế phải bằng giá niêm yết của hạng vé."),
            50060 => (HttpStatusCode.UnprocessableEntity, "Refund Exceeds Payment", "Tổng tiền hoàn vượt quá số tiền đã thanh toán."),
            50070 => (HttpStatusCode.Conflict, "Duplicate Effective Payment", "Booking này đã có giao dịch thanh toán có hiệu lực."),
            50080 => (HttpStatusCode.BadRequest, "Discount Code Required", "Khuyến mãi này bắt buộc phải có mã giảm giá."),
            50090 or 50091 => (HttpStatusCode.BadRequest, "Promotion Not Valid", "Khuyến mãi hoặc mã giảm giá không còn hiệu lực tại thời điểm áp dụng."),
            50100 => (HttpStatusCode.Forbidden, "Audit Immutable", "Bản ghi kiểm toán không được sửa hoặc xóa."),
            50110 => (HttpStatusCode.Forbidden, "System Actor Required", "Sự kiện hệ thống phải ghi nhận bởi tài khoản hệ thống."),
            50111 or 50112 => (HttpStatusCode.Forbidden, "Session Context Invalid", "Phiên làm việc không hợp lệ. Vui lòng đăng nhập lại."),
            50120 => (HttpStatusCode.BadRequest, "Seat Venue Inconsistent", "Ghế phải thuộc đúng địa điểm của khu vực."),
            50130 or 50131 => (HttpStatusCode.Conflict, "Venue Change Blocked", "Không thể đổi địa điểm khi đã có kho vé tham chiếu."),

            // Lỗi cấu hình hệ thống (thiếu bản ghi SystemConfiguration bắt buộc — §23.7).
            // Đây thực sự là 500: không phải người gọi làm sai, mà dữ liệu nền chưa đủ.
            // Vẫn map tường minh để thông báo nói đúng nguyên nhân thay vì "lỗi cơ sở dữ liệu".
            58705 or 59301 or 59701 => (HttpStatusCode.InternalServerError, "System Configuration Missing",
                      "Thiếu bản ghi cấu hình hệ thống bắt buộc. Liên hệ quản trị viên."),

            // Duplicate Key (2627 = constraint, 2601 = unique index)
            2627 or 2601 => (HttpStatusCode.Conflict, "Duplicate Entry", "Bản ghi đã tồn tại."),

            _ => (HttpStatusCode.InternalServerError, "Database Error", "Đã xảy ra lỗi cơ sở dữ liệu (Code: " + ex.Number + ").")
        };
    }
}
