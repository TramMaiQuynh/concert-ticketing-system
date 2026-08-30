using System;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Xunit;
using FluentAssertions;
using Moq;
using ConcertTicketing.API.Controllers;
using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Application.Interfaces;

namespace ConcertTicketing.UnitTests.API.Controllers;

public class PaymentControllerTests
{
    private readonly Mock<IPaymentRepository> _mockRepo;
    private readonly Mock<ILogger<PaymentController>> _mockLogger;
    private readonly PaymentController _controller;

    public PaymentControllerTests()
    {
        _mockRepo = new Mock<IPaymentRepository>();
        _mockLogger = new Mock<ILogger<PaymentController>>();

        var user = new ClaimsPrincipal(new ClaimsIdentity(new Claim[]
        {
            new Claim(ClaimTypes.NameIdentifier, "42")
        }, "mock"));

        var httpContext = new DefaultHttpContext { User = user };
        _controller = new PaymentController(_mockRepo.Object, _mockLogger.Object)
        {
            ControllerContext = new ControllerContext { HttpContext = httpContext }
        };
    }

    [Fact]
    public async Task InitiatePayment_Returns200()
    {
        var request = new InitiatePaymentRequest();
        var response = new InitiatePaymentResponse(1, "http://url", "REF-123", 100);
        _mockRepo.Setup(r => r.InitiateAsync(10, 42)).ReturnsAsync(response);

        var result = await _controller.InitiatePayment(10, request);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().Be(response);
    }

    [Fact]
    public async Task InitiatePayment_NoUserClaim_Returns401()
    {
        _controller.ControllerContext.HttpContext.User = new ClaimsPrincipal();
        
        var request = new InitiatePaymentRequest();
        var result = await _controller.InitiatePayment(10, request);

        result.Should().BeOfType<UnauthorizedResult>();
    }

    [Fact]
    public async Task ConfirmPayment_Success_Returns200()
    {
        var result = await _controller.ConfirmPayment(10, 1, "PROVIDER-REF");

        _mockRepo.Verify(r => r.ConfirmAsync(10, 1, "PROVIDER-REF"), Times.Once);
        result.Should().BeOfType<OkObjectResult>();
    }

    [Fact]
    public async Task ConfirmPayment_RepoThrows_Returns400()
    {
        _mockRepo.Setup(r => r.ConfirmAsync(10, 1, "PROVIDER-REF"))
            .ThrowsAsync(new ArgumentException("Invalid state"));

        var result = await _controller.ConfirmPayment(10, 1, "PROVIDER-REF");
        
        result.Should().BeOfType<BadRequestObjectResult>();
    }

    [Fact]
    public async Task RefundPayment_Returns200WithRefundId()
    {
        var request = new RefundRequest(50, "Customer request");
        _mockRepo.Setup(r => r.ProcessRefundAsync(1, 50, "Customer request", 42)).ReturnsAsync(99);

        var result = await _controller.RefundPayment(1, request);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        // In the controller it returns new { RefundId = refundId }
        okResult.Value.Should().BeEquivalentTo(new { RefundId = 99 });
    }
}
