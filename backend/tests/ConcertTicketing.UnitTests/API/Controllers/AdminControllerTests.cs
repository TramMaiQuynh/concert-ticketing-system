using System;
using System.Collections.Generic;
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

public class AdminControllerTests
{
    private readonly Mock<IAdminRepository> _mockRepo;
    private readonly AdminController _controller;

    public AdminControllerTests()
    {
        _mockRepo = new Mock<IAdminRepository>();

        var user = new ClaimsPrincipal(new ClaimsIdentity(new Claim[]
        {
            new Claim(ClaimTypes.NameIdentifier, "7")
        }, "mock"));

        var httpContext = new DefaultHttpContext { User = user };
        _controller = new AdminController(_mockRepo.Object)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
    }

    [Fact]
    public async Task CreateConcert_Returns201WithId()
    {
        var request = new CreateConcertRequest(1, 2, "Spring Tour", DateTime.UtcNow,
            DateTime.UtcNow.AddDays(1));
        _mockRepo.Setup(r => r.CreateConcertAsync(7, request)).ReturnsAsync(11);

        var result = await _controller.CreateConcert(request);

        var created = result.Should().BeOfType<CreatedResult>().Subject;
        created.Value.Should().BeEquivalentTo(new { Id = 11 });
    }

    [Fact]
    public async Task UpdateConcert_Returns204()
    {
        var request = new UpdateConcertRequest(ConcertName: "Renamed");
        _mockRepo.Setup(r => r.UpdateConcertAsync(5, 7, request)).Returns(Task.CompletedTask);

        var result = await _controller.UpdateConcert(5, request);

        result.Should().BeOfType<NoContentResult>();
        _mockRepo.Verify(r => r.UpdateConcertAsync(5, 7, request), Times.Once);
    }

    [Fact]
    public async Task UpdateConcertStatus_Returns204()
    {
        var request = new UpdateConcertStatusRequest("Published");
        _mockRepo.Setup(r => r.UpdateConcertStatusAsync(5, 7, "Published")).Returns(Task.CompletedTask);

        var result = await _controller.UpdateConcertStatus(5, request);

        result.Should().BeOfType<NoContentResult>();
        _mockRepo.Verify(r => r.UpdateConcertStatusAsync(5, 7, "Published"), Times.Once);
    }

    [Fact]
    public async Task CreateDiscountCode_Returns201WithId()
    {
        var request = new CreateDiscountCodeRequest("EARLY50");
        _mockRepo.Setup(r => r.CreateDiscountCodeAsync(7, 3, request)).ReturnsAsync(21);

        var result = await _controller.CreateDiscountCode(3, request);

        var created = result.Should().BeOfType<CreatedResult>().Subject;
        created.Value.Should().BeEquivalentTo(new { Id = 21 });
    }

    [Fact]
    public async Task SetEventSeatUnavailable_Returns204()
    {
        var request = new SetEventSeatUnavailableRequest(true, "Repair works");
        _mockRepo.Setup(r => r.SetEventSeatUnavailableAsync(7, 4, request)).Returns(Task.CompletedTask);

        var result = await _controller.SetEventSeatUnavailable(4, request);

        result.Should().BeOfType<NoContentResult>();
        _mockRepo.Verify(r => r.SetEventSeatUnavailableAsync(7, 4, request), Times.Once);
    }

    [Fact]
    public async Task UpdateUserStatus_Returns204()
    {
        var request = new UpdateUserStatusRequest("Locked");
        _mockRepo.Setup(r => r.UpdateUserStatusAsync(7, 8, request)).Returns(Task.CompletedTask);

        var result = await _controller.UpdateUserStatus(8, request);

        result.Should().BeOfType<NoContentResult>();
        _mockRepo.Verify(r => r.UpdateUserStatusAsync(7, 8, request), Times.Once);
    }

    [Fact]
    public async Task AddCheckinStaffAssignment_Returns204()
    {
        var request = new AddCheckinStaffAssignmentRequest(9, new List<int> { 1, 2 });
        _mockRepo.Setup(r => r.AddCheckinStaffAssignmentAsync(7, request)).Returns(Task.CompletedTask);

        var result = await _controller.AddCheckinStaffAssignment(request);

        result.Should().BeOfType<NoContentResult>();
        _mockRepo.Verify(r => r.AddCheckinStaffAssignmentAsync(7, request), Times.Once);
    }

    [Fact]
    public async Task CreateVenue_Returns201WithId()
    {
        var request = new CreateVenueRequest("Grand Arena", "HCMC");
        _mockRepo.Setup(r => r.CreateVenueAsync(7, request)).ReturnsAsync(30);

        var result = await _controller.CreateVenue(request);

        var created = result.Should().BeOfType<CreatedResult>().Subject;
        created.Value.Should().BeEquivalentTo(new { Id = 30 });
    }

    [Fact]
    public async Task Request_NoUserClaim_ThrowsUnauthorized()
    {
        _controller.ControllerContext.HttpContext.User = new ClaimsPrincipal();

        var request = new CreateConcertRequest(1, 2, "X", DateTime.UtcNow, DateTime.UtcNow.AddDays(1));
        var act = async () => await _controller.CreateConcert(request);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }
}