using Hangfire.Dashboard;
using System.Security.Claims;

namespace ConcertTicketing.API;

/// <summary>
/// Bộ lọc xác thực cho Hangfire Dashboard.
/// Chỉ cho phép user có Role = "Admin" truy cập /hangfire.
/// </summary>
public class HangfireAdminAuthFilter : IDashboardAuthorizationFilter
{
    public bool Authorize(DashboardContext context)
    {
        var httpContext = context.GetHttpContext();
        return Authorize(httpContext);
    }

    public bool Authorize(HttpContext? httpContext)
    {
        // Phải đăng nhập
        if (httpContext?.User?.Identity?.IsAuthenticated != true)
            return false;

        // Phải có role Admin
        return httpContext.User.IsInRole("Admin");
    }
}
