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
            type = $"https://api.concert.vn/errors/{title.ToLower().Replace(" ", "-")}",
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

    /// <summary>
    /// Map SQL Error Numbers từ Stored Procedures → HTTP Status Codes.
    /// Xem: database/StoredProcedures/ để biết nguồn gốc từng error number.
    /// </summary>
    private static (HttpStatusCode, string, string) MapSqlException(SqlException ex)
    {
        return ex.Number switch
        {
            // sp_CreateBooking
            51001 => (HttpStatusCode.BadRequest, "Concert Not On Sale",
                      "Concert hiện không trong trạng thái mở bán vé."),
            51002 => (HttpStatusCode.BadRequest, "Empty Seat List",
                      "Danh sách ghế không được để trống."),
            51003 => (HttpStatusCode.UnprocessableEntity, "Purchase Limit Exceeded",
                      "Bạn đã vượt quá giới hạn số vé được mua cho concert này."),
            51004 => (HttpStatusCode.Conflict, "Seat Unavailable",
                      "Một hoặc nhiều ghế bạn chọn đã được người khác đặt. Vui lòng chọn ghế khác."),
            51005 => (HttpStatusCode.BadRequest, "Invalid Waitlist Entry",
                      "Thông tin hàng đợi không hợp lệ."),

            // sp_ConfirmPayment
            52001 => (HttpStatusCode.NotFound, "Booking Not Found",
                      "Booking không tồn tại trong hệ thống."),
            52002 => (HttpStatusCode.Conflict, "Booking Not Pending",
                      "Booking này không ở trạng thái chờ thanh toán."),
            52003 => (HttpStatusCode.Gone, "Booking Expired",
                      "Thời gian giữ chỗ đã hết hạn. Vui lòng đặt lại."),
            52005 => (HttpStatusCode.BadRequest, "Payment Amount Mismatch",
                      "Số tiền thanh toán không khớp với tổng hóa đơn."),

            // sp_ProcessRefund
            53001 => (HttpStatusCode.NotFound, "Payment Not Found",
                      "Thông tin thanh toán không tồn tại."),
            53004 => (HttpStatusCode.UnprocessableEntity, "Refund Exceeds Payment",
                      "Số tiền hoàn trả vượt quá số tiền đã thanh toán."),

            // sp_ApplyPromotion
            54006 => (HttpStatusCode.BadRequest, "Promotion Expired",
                      "Mã khuyến mãi đã hết hiệu lực."),
            54009 => (HttpStatusCode.BadRequest, "Invalid Discount Code",
                      "Mã khuyến mãi không hợp lệ."),

            // Duplicate Key (Webhook idempotency) — KHÔNG được trả lỗi cho Cổng thanh toán
            // Được xử lý riêng trong PaymentController, không nên tới đây
            2627 => (HttpStatusCode.Conflict, "Duplicate Entry",
                     "Bản ghi đã tồn tại."),

            // Mặc định
            _ => (HttpStatusCode.InternalServerError, "Database Error",
                  $"Đã xảy ra lỗi cơ sở dữ liệu (Code: {ex.Number}).")
        };
    }
}
