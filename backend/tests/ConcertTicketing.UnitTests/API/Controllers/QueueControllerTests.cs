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

public class QueueControllerTests
{
    private readonly Mock<IQueueRepository> _mockRepo;
    private readonly QueueController _controller;

    public QueueControllerTests()
    {
        _mockRepo = new Mock<IQueueRepository>();

        var user = new ClaimsPrincipal(new ClaimsIdentity(new Claim[]
        {
            new Claim(ClaimTypes.NameIdentifier, "17")
        }, "mock"));

        var httpContext = new DefaultHttpContext { User = user };
        _controller = new QueueController(_mockRepo.Object)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
    }

    [Fact]
    public async Task Join_Returns200WithEntry()
    {
        var resp = new JoinQueueResponse(40, "Waiting", DateTime.UtcNow);
        _mockRepo.Setup(r => r.JoinAsync(17, 3)).ReturnsAsync(resp);

        var result = await _controller.Join(3);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(resp);
    }

    [Fact]
    public async Task GetMyEntry_Found_Returns200()
    {
        var entry = new QueueEntryStatusDto(40, "Waiting", DateTime.UtcNow, null, null);
        _mockRepo.Setup(r => r.GetMyEntryAsync(17, 3)).ReturnsAsync(entry);

        var result = await _controller.GetMyEntry(3);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(entry);
    }

    [Fact]
    public async Task GetMyEntry_NotFound_Returns404()
    {
        _mockRepo.Setup(r => r.GetMyEntryAsync(17, 3)).ReturnsAsync((QueueEntryStatusDto?)null);

        var result = await _controller.GetMyEntry(3);

        result.Should().BeOfType<NotFoundResult>();
    }

    [Fact]
    public async Task Join_NoUserClaim_ThrowsUnauthorized()
    {
        _controller.ControllerContext.HttpContext.User = new ClaimsPrincipal();

        var act = async () => await _controller.Join(3);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }
}