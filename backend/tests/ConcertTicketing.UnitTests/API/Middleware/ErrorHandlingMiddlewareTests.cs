using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;
using Xunit;
using FluentAssertions;
using Moq;
using ConcertTicketing.API.Middleware;

namespace ConcertTicketing.UnitTests.API.Middleware;

public class ErrorHandlingMiddlewareTests
{
    private readonly Mock<ILogger<ErrorHandlingMiddleware>> _mockLogger;

    public ErrorHandlingMiddlewareTests()
    {
        _mockLogger = new Mock<ILogger<ErrorHandlingMiddleware>>();
    }

    [Fact]
    public async Task ArgumentException_Returns400()
    {
        var middleware = new ErrorHandlingMiddleware(
            innerHttpContext => throw new ArgumentException("Bad argument"), 
            _mockLogger.Object);
            
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(400);
    }

    [Fact]
    public async Task UnauthorizedAccessException_Returns401()
    {
        var middleware = new ErrorHandlingMiddleware(
            innerHttpContext => throw new UnauthorizedAccessException("Not allowed"), 
            _mockLogger.Object);
            
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(401);
    }

    [Fact]
    public async Task UnknownException_Returns500()
    {
        var middleware = new ErrorHandlingMiddleware(
            innerHttpContext => throw new Exception("Unknown server error"), 
            _mockLogger.Object);
            
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(500);
    }

    [Fact]
    public async Task ResponseBody_IsRfc7807Format()
    {
        var middleware = new ErrorHandlingMiddleware(
            innerHttpContext => throw new ArgumentException("Missing parameter"), 
            _mockLogger.Object);
            
        var context = new DefaultHttpContext();
        context.Request.Path = "/api/test";
        var memoryStream = new MemoryStream();
        context.Response.Body = memoryStream;

        await middleware.InvokeAsync(context);

        memoryStream.Seek(0, SeekOrigin.Begin);
        var reader = new StreamReader(memoryStream);
        var jsonResponse = await reader.ReadToEndAsync();

        var pd = JsonSerializer.Deserialize<ProblemDetails>(jsonResponse, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
        
        pd.Should().NotBeNull();
        pd!.Status.Should().Be(400);
        pd.Title.Should().Be("Invalid Argument");
        pd.Detail.Should().Be("Missing parameter");
        pd.Instance.Should().Be("/api/test");
        pd.Type.Should().Be("https://api.concert.vn/errors/invalid-argument");
        
        // Assert extensions contains traceId
        pd.Extensions.Should().ContainKey("traceId");
    }

    [Fact]
    public async Task ContentType_IsProblemJson()
    {
        var middleware = new ErrorHandlingMiddleware(
            innerHttpContext => throw new ArgumentException("Bad argument"), 
            _mockLogger.Object);
            
        var context = new DefaultHttpContext();
        context.Response.Body = new MemoryStream();

        await middleware.InvokeAsync(context);

        context.Response.ContentType.Should().Be("application/problem+json");
    }

    [Fact]
    public async Task NoException_PassesThrough()
    {
        var middleware = new ErrorHandlingMiddleware(
            async innerHttpContext => 
            {
                innerHttpContext.Response.StatusCode = 200;
                await Task.CompletedTask;
            }, 
            _mockLogger.Object);
            
        var context = new DefaultHttpContext();

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(200);
    }
}
