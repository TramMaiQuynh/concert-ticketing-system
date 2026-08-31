using System;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Xunit;
using FluentAssertions;
using Moq;
using ConcertTicketing.API.Controllers;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.UnitTests.API.Controllers;

public class WaitlistControllerTests
{
    private readonly Mock<IWaitlistRepository> _mockRepo;
    private readonly WaitlistController _controller;

    public WaitlistControllerTests()
    {
        _mockRepo = new Mock<IWaitlistRepository>();

        var user = new ClaimsPrincipal(new ClaimsIdentity(new Claim[]
        {
            new Claim(ClaimTypes.NameIdentifier, "15")
        }, "mock"));

        var httpContext = new DefaultHttpContext { User = user };
        _controller = new WaitlistController(_mockRepo.Object)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
    }

    [Fact]
    public async Task Join_Returns200WithEntry()
    {
        var resp = new WaitlistJoinResponse(30, 1);
        _mockRepo.Setup(r => r.JoinAsync(15, 2)).ReturnsAsync(resp);

        var result = await _controller.Join(2);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(resp);
    }

    [Fact]
    public async Task GetMyEntry_Found_Returns200()
    {
        var entry = new WaitlistEntryStatusDto(30, "Active", 1, DateTime.UtcNow, null, null);
        _mockRepo.Setup(r => r.GetMyEntryAsync(15, 2)).ReturnsAsync(entry);

        var result = await _controller.GetMyEntry(2);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(entry);
    }

    [Fact]
    public async Task GetMyEntry_NotFound_Returns404()
    {
        _mockRepo.Setup(r => r.GetMyEntryAsync(15, 2)).ReturnsAsync((WaitlistEntryStatusDto?)null);

        var result = await _controller.GetMyEntry(2);

        result.Should().BeOfType<NotFoundResult>();
    }

    [Fact]
    public async Task Join_NoUserClaim_ThrowsUnauthorized()
    {
        _controller.ControllerContext.HttpContext.User = new ClaimsPrincipal();

        var act = async () => await _controller.Join(2);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }
}