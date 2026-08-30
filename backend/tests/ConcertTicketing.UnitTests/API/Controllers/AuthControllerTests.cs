using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Xunit;
using FluentAssertions;
using Moq;
using ConcertTicketing.API.Controllers;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Services;
using System.Collections.Generic;

namespace ConcertTicketing.UnitTests.API.Controllers;

public class AuthControllerTests
{
    private readonly Mock<IAuthService> _mockAuthService;
    private readonly IConfiguration _config;
    private readonly AuthController _controller;

    public AuthControllerTests()
    {
        _mockAuthService = new Mock<IAuthService>();
        
        var inMemorySettings = new Dictionary<string, string> { {"Jwt:RefreshTokenExpiryDays", "7"} };
        _config = new ConfigurationBuilder().AddInMemoryCollection(inMemorySettings!).Build();

        var httpContext = new DefaultHttpContext();
        _controller = new AuthController(_mockAuthService.Object, _config)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
    }

    [Fact]
    public async Task Login_Success_Returns200WithAuthResponse()
    {
        var request = new LoginRequest("test", "pass");
        var response = new AuthResponse("token", "Bearer", 900);
        _mockAuthService.Setup(s => s.LoginAsync(request))
            .ReturnsAsync((response, "raw-token"));

        var result = await _controller.Login(request);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task Login_ShouldSetRefreshTokenCookie()
    {
        var request = new LoginRequest("test", "pass");
        _mockAuthService.Setup(s => s.LoginAsync(request))
            .ReturnsAsync((new AuthResponse("token", "Bearer", 900), "raw-refresh-token"));

        await _controller.Login(request);

        var cookies = _controller.Response.Headers["Set-Cookie"].ToString();
        cookies.Should().Contain("rt=raw-refresh-token");
        cookies.Should().Contain("httponly");
    }

    [Fact]
    public async Task Register_Success_Returns201()
    {
        var request = new RegisterRequest("test", "test@test.com", "pass", "Test");
        var response = new AuthResponse("token", "Bearer", 900);
        _mockAuthService.Setup(s => s.RegisterAsync(request))
            .ReturnsAsync((response, "raw-token"));

        var result = await _controller.Register(request);

        var statusCodeResult = result.Should().BeOfType<ObjectResult>().Subject;
        statusCodeResult.StatusCode.Should().Be(201);
        statusCodeResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task Refresh_NoCookie_Returns401()
    {
        // No cookies set on request
        var result = await _controller.Refresh();

        var unauthorizedResult = result.Should().BeOfType<UnauthorizedObjectResult>().Subject;
        unauthorizedResult.Value.Should().Be("Refresh token không tồn tại.");
    }

    [Fact]
    public async Task Refresh_ValidCookie_Returns200()
    {
        _controller.Request.Headers["Cookie"] = "rt=valid-token";
        
        var response = new AuthResponse("new-access-token", "Bearer", 900);
        _mockAuthService.Setup(s => s.RefreshAsync("valid-token"))
            .ReturnsAsync((response, "new-refresh-token"));

        var result = await _controller.Refresh();

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task Refresh_ShouldOverwriteCookie()
    {
        _controller.Request.Headers["Cookie"] = "rt=valid-token";
        
        _mockAuthService.Setup(s => s.RefreshAsync("valid-token"))
            .ReturnsAsync((new AuthResponse("token", "Bearer", 900), "new-refresh-token"));

        await _controller.Refresh();

        var cookies = _controller.Response.Headers["Set-Cookie"].ToString();
        cookies.Should().Contain("rt=new-refresh-token");
    }

    [Fact]
    public async Task Logout_WithCookie_CallsRevokeAndDeletesCookie()
    {
        _controller.Request.Headers["Cookie"] = "rt=valid-token";

        var result = await _controller.Logout();

        _mockAuthService.Verify(s => s.LogoutAsync("valid-token"), Times.Once);
        result.Should().BeOfType<NoContentResult>();
        
        var cookies = _controller.Response.Headers["Set-Cookie"].ToString();
        cookies.Should().Contain("rt=;"); // Cookie deletion format
    }

    [Fact]
    public async Task Logout_WithoutCookie_StillReturns204()
    {
        var result = await _controller.Logout();

        _mockAuthService.Verify(s => s.LogoutAsync(It.IsAny<string>()), Times.Never);
        result.Should().BeOfType<NoContentResult>();
    }
}
