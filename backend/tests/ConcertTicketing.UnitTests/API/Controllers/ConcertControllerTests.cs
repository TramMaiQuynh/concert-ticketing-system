using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Xunit;
using FluentAssertions;
using Moq;
using ConcertTicketing.API.Controllers;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.UnitTests.API.Controllers;

public class ConcertControllerTests
{
    private readonly Mock<IConcertRepository> _mockRepo;
    private readonly Mock<ISeatMapCache> _mockCache;
    private readonly ConcertController _controller;

    public ConcertControllerTests()
    {
        _mockRepo = new Mock<IConcertRepository>();
        _mockCache = new Mock<ISeatMapCache>();
        _controller = new ConcertController(_mockRepo.Object, _mockCache.Object);
    }

    [Fact]
    public async Task GetList_DefaultPagination_Returns200()
    {
        var items = new List<ConcertListItem>();
        _mockRepo.Setup(r => r.GetListAsync(1, 20, null)).ReturnsAsync(items);

        var result = await _controller.GetList();

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(items);
        _mockRepo.Verify(r => r.GetListAsync(1, 20, null), Times.Once);
    }

    [Fact]
    public async Task GetList_InvalidPage_ClampsTo1()
    {
        var items = new List<ConcertListItem>();
        _mockRepo.Setup(r => r.GetListAsync(1, 20, null)).ReturnsAsync(items);

        var result = await _controller.GetList(page: -1);

        result.Should().BeOfType<OkObjectResult>();
        _mockRepo.Verify(r => r.GetListAsync(1, 20, null), Times.Once);
    }

    [Fact]
    public async Task GetList_PageSizeTooLarge_ClampsTo20()
    {
        var items = new List<ConcertListItem>();
        _mockRepo.Setup(r => r.GetListAsync(1, 20, null)).ReturnsAsync(items);

        var result = await _controller.GetList(pageSize: 999);

        result.Should().BeOfType<OkObjectResult>();
        _mockRepo.Verify(r => r.GetListAsync(1, 20, null), Times.Once);
    }

    [Fact]
    public async Task GetById_NotFound_Returns404()
    {
        _mockRepo.Setup(r => r.GetByIdAsync(99)).ReturnsAsync((ConcertDetail?)null);

        var result = await _controller.GetById(99);

        result.Should().BeOfType<NotFoundResult>();
    }

    [Fact]
    public async Task GetSeats_Returns200FromCache()
    {
        var seats = new List<SeatDto>();
        _mockCache.Setup(c => c.GetSeatsAsync(1, It.IsAny<CancellationToken>())).ReturnsAsync(seats);

        var result = await _controller.GetSeats(1, CancellationToken.None);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(seats);
    }
}
