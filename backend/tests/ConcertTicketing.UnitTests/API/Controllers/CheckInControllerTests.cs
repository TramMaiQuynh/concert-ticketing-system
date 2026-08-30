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

public class CheckInControllerTests
{
    private readonly Mock<ICheckInRepository> _mockRepo;
    private readonly CheckInController _controller;

    public CheckInControllerTests()
    {
        _mockRepo = new Mock<ICheckInRepository>();

        var user = new ClaimsPrincipal(new ClaimsIdentity(new Claim[]
        {
            new Claim(ClaimTypes.NameIdentifier, "99")
        }, "mock"));

        var httpContext = new DefaultHttpContext { User = user };
        _controller = new CheckInController(_mockRepo.Object)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
    }

    [Fact]
    public async Task CheckIn_ValidRequest_Returns200()
    {
        var request = new CheckInRequest("TKT-123", 1);
        var response = new CheckInResponse("SUCCESS", "Valid", DateTime.UtcNow);
        _mockRepo.Setup(r => r.CheckInAsync(99, request)).ReturnsAsync(response);

        var result = await _controller.CheckIn(request);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task CheckIn_AlwaysReturns200EvenIfInvalid()
    {
        var request = new CheckInRequest("TKT-123", 1);
        var response = new CheckInResponse("INVALID", "Fake ticket", null);
        _mockRepo.Setup(r => r.CheckInAsync(99, request)).ReturnsAsync(response);

        var result = await _controller.CheckIn(request);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task CheckIn_NoUserClaim_ThrowsUnauthorized()
    {
        _controller.ControllerContext.HttpContext.User = new ClaimsPrincipal(); // Empty
        
        var request = new CheckInRequest("TKT-123", 1);
        
        var act = async () => await _controller.CheckIn(request);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }
}
