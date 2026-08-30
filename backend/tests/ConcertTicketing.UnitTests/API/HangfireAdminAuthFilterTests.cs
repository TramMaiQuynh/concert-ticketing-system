using System.Collections.Generic;
using System.Security.Claims;
using Microsoft.AspNetCore.Http;
using Xunit;
using FluentAssertions;
using Moq;
using Hangfire.Dashboard;
using ConcertTicketing.API;

namespace ConcertTicketing.UnitTests.API;

public class HangfireAdminAuthFilterTests
{
    private readonly HangfireAdminAuthFilter _filter = new();
    private readonly Mock<DashboardContext> _mockContext = new();
    private readonly DefaultHttpContext _httpContext = new();

    public HangfireAdminAuthFilterTests()
    {
    }

    [Fact]
    public void Unauthenticated_ReturnsFalse()
    {
        _httpContext.User = new ClaimsPrincipal(new ClaimsIdentity());

        var result = _filter.Authorize(_httpContext);

        result.Should().BeFalse();
    }

    [Fact]
    public void AuthenticatedButNotAdmin_ReturnsFalse()
    {
        var identity = new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.Role, "Customer")
        }, "mock");
        _httpContext.User = new ClaimsPrincipal(identity);

        var result = _filter.Authorize(_httpContext);

        result.Should().BeFalse();
    }

    [Fact]
    public void AuthenticatedAdmin_ReturnsTrue()
    {
        var identity = new ClaimsIdentity(new[]
        {
            new Claim(ClaimTypes.Role, "Admin")
        }, "mock");
        _httpContext.User = new ClaimsPrincipal(identity);

        var result = _filter.Authorize(_httpContext);

        result.Should().BeTrue();
    }
}
