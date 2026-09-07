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
        _mockRepo.Setup(r => r.ConfirmAsync(10, 1, "SIG-ABC", "PROVIDER-REF"))
            .ReturnsAsync(new ConfirmPaymentResult(PaymentConfirmOutcome.Confirmed, true, "ok"));

        var result = await _controller.ConfirmPayment(10, 1, "SIG-ABC", "PROVIDER-REF");

        _mockRepo.Verify(r => r.ConfirmAsync(10, 1, "SIG-ABC", "PROVIDER-REF"), Times.Once);
        var ok = result.Should().BeOfType<OkObjectResult>().Subject;
        ok.Value!.GetType().GetProperty("BookingConfirmed")!.GetValue(ok.Value)
            .Should().Be(true);
    }

    /// <summary>
    /// Webhook vẫn trả 200 (cổng thanh toán không cần gửi lại), NHƯNG body phải nói rõ
    /// đơn hàng KHÔNG được xác nhận. Trước đây endpoint luôn trả "Payment confirmed
    /// successfully" kể cả khi sp_ConfirmPayment đã tạo yêu cầu hoàn tiền vì lệch số
    /// tiền — tức báo sai cho cả cổng thanh toán lẫn client đang chờ kết quả.
    /// </summary>
    [Theory]
    [InlineData(PaymentConfirmOutcome.AutoRefundedAmountMismatch)]
    [InlineData(PaymentConfirmOutcome.AutoRefundedDuplicatePayment)]
    [InlineData(PaymentConfirmOutcome.AutoRefundedBookingNotPending)]
    [InlineData(PaymentConfirmOutcome.AlreadyRefunded)]
    public async Task ConfirmPayment_AutoRefunded_Returns200ButNotConfirmed(PaymentConfirmOutcome outcome)
    {
        _mockRepo.Setup(r => r.ConfirmAsync(10, 1, "SIG-ABC", "PROVIDER-REF"))
            .ReturnsAsync(new ConfirmPaymentResult(outcome, false, "đã tạo yêu cầu hoàn tiền"));

        var result = await _controller.ConfirmPayment(10, 1, "SIG-ABC", "PROVIDER-REF");

        var ok = result.Should().BeOfType<OkObjectResult>().Subject;
        var v = ok.Value!;
        v.GetType().GetProperty("BookingConfirmed")!.GetValue(v).Should().Be(false);
        v.GetType().GetProperty("Outcome")!.GetValue(v).Should().Be(outcome.ToString());
    }

    [Fact]
    public async Task ConfirmPayment_InvalidSignature_ThrowsUnauthorized()
    {
        _mockRepo.Setup(r => r.ConfirmAsync(10, 1, "WRONG", "PROVIDER-REF"))
            .ThrowsAsync(new UnauthorizedAccessException("Chữ ký thanh toán không hợp lệ."));

        var act = async () => await _controller.ConfirmPayment(10, 1, "WRONG", "PROVIDER-REF");

        await act.Should().ThrowAsync<UnauthorizedAccessException>();
    }

    [Fact]
    public async Task RefundBooking_Returns200WithRefundId()
    {
        var request = new RefundRequest("Customer request");
        _mockRepo.Setup(r => r.ProcessRefundAsync(1, "Customer request", 42, false)).ReturnsAsync(99);

        var result = await _controller.RefundBooking(1, request);

        var okResult = result.Should().BeOfType<OkObjectResult>().Subject;
        okResult.Value.Should().BeEquivalentTo(new { RefundId = 99 });
    }
}
