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

public class BookingControllerTests
{
    private readonly Mock<IBookingRepository> _mockRepo;
    private readonly BookingController _controller;

    public BookingControllerTests()
    {
        _mockRepo = new Mock<IBookingRepository>();
        
        var user = new ClaimsPrincipal(new ClaimsIdentity(new Claim[]
        {
            new Claim(ClaimTypes.NameIdentifier, "1")
        }, "mock"));

        var httpContext = new DefaultHttpContext { User = user };
        _controller = new BookingController(_mockRepo.Object)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
    }

    [Fact]
    public async Task Create_ValidRequest_Returns201()
    {
        var request = new CreateBookingRequest(1, new List<int> { 1, 2 });
        var response = new CreateBookingResponse(10, "BKG-000010", DateTime.UtcNow, 100, 100, "Pending");
        _mockRepo.Setup(r => r.CreateAsync(1, request)).ReturnsAsync(response);

        var result = await _controller.Create(request);

        var objectResult = result.Should().BeOfType<ObjectResult>().Subject;
        objectResult.StatusCode.Should().Be(201);
        objectResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task Create_NoUserClaim_ThrowsUnauthorized()
    {
        _controller.ControllerContext.HttpContext.User = new ClaimsPrincipal(); // No claims
        
        var request = new CreateBookingRequest(1, new List<int> { 1 });
        var act = async () => await _controller.Create(request);

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task GetById_Found_Returns200()
    {
        var response = new BookingDetail(10, 1, "Concert", "Pending", DateTime.UtcNow, null, 100, 0, 100, "BKG-000010", new List<BookingAllocationDto>());
        _mockRepo.Setup(r => r.GetByIdAsync(10, 1)).ReturnsAsync(response);

        var result = await _controller.GetById(10);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task GetById_NotFound_Returns404()
    {
        _mockRepo.Setup(r => r.GetByIdAsync(10, 1)).ReturnsAsync((BookingDetail?)null);

        var result = await _controller.GetById(10);

        result.Should().BeOfType<NotFoundResult>();
    }

    [Fact]
    public async Task ApplyPromotion_Returns204()
    {
        var request = new ApplyPromotionRequest("DISCOUNT");
        
        var result = await _controller.ApplyPromotion(10, request);

        _mockRepo.Verify(r => r.ApplyPromotionAsync(10, 1, "DISCOUNT"), Times.Once);
        result.Should().BeOfType<NoContentResult>();
    }

    [Fact]
    public async Task Cancel_Returns204()
    {
        var result = await _controller.Cancel(10);

        _mockRepo.Verify(r => r.CancelAsync(10, 1), Times.Once);
        result.Should().BeOfType<NoContentResult>();
    }
}
