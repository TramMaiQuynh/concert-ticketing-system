using System;
using System.Reflection;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;
using Xunit;
using FluentAssertions;
using Moq;
using ConcertTicketing.API.Middleware;

namespace ConcertTicketing.UnitTests.API.Middleware;

/// <summary>
/// Validates that the new stored-procedure error codes (admin management,
/// waitlist, queue, discount code, event-seat availability, user status,
/// check-in staff) map to the correct HTTP status codes.
/// </summary>
public class ExtendedErrorMappingTests
{
    private readonly Mock<ILogger<ErrorHandlingMiddleware>> _mockLogger = new();

    public static TheoryData<int, int> ErrorCodeMappings => new()
    {
        // sp_CreateConcert / sp_UpdateConcert / sp_UpdateConcertStatus
        { 58001, 400 }, { 58002, 400 }, { 58003, 400 }, { 58004, 400 },
        { 58005, 400 }, { 58006, 400 }, { 58010, 404 }, { 58011, 409 },
        { 58012, 403 }, { 58013, 400 }, { 58020, 400 }, { 58021, 404 }, { 58022, 403 },

        // sp_CreateVenue / sp_CreateZone / sp_CreateSeat
        { 58101, 403 }, { 58102, 400 }, { 58111, 403 }, { 58112, 400 },
        { 58113, 400 }, { 58121, 403 }, { 58122, 400 }, { 58123, 400 },

        // sp_ConfigureTicketCategory / sp_AddEventSeats
        { 58201, 404 }, { 58202, 403 }, { 58203, 400 }, { 58211, 404 },
        { 58212, 403 }, { 58213, 400 }, { 58214, 400 }, { 58215, 400 },
        { 58216, 400 }, { 58217, 409 },

        // sp_CreatePromotion
        { 58301, 404 }, { 58302, 403 }, { 58303, 400 }, { 58304, 400 }, { 58305, 400 },

        // sp_AssignRole
        { 58401, 403 }, { 58402, 400 }, { 58403, 400 }, { 58404, 403 },

        // sp_JoinWaitlist
        { 58501, 404 }, { 58502, 409 }, { 58503, 409 },

        // sp_CreateDiscountCode
        { 58601, 403 }, { 58602, 400 }, { 58603, 400 },

        // sp_JoinQueue
        { 58701, 404 }, { 58702, 409 }, { 58703, 409 },

        // sp_SetEventSeatUnavailable
        { 58801, 404 }, { 58802, 403 }, { 58803, 400 }, { 58804, 400 },

        // sp_AdminUpdateUserStatus
        { 58901, 403 }, { 58902, 400 }, { 58903, 404 }, { 58904, 403 },

        // sp_AddCheckinStaffAssignment
        { 59001, 403 }, { 59002, 404 }, { 59003, 400 }, { 59004, 400 },

        // State Machine (BR49) — TRG_*_StateTransition
        { 50001, 409 }, { 50002, 409 }, { 50003, 409 }, { 50004, 409 },
        { 50005, 409 }, { 50006, 409 }, { 50007, 409 }, { 50008, 409 },
        { 50009, 409 }, { 50010, 409 },

        // Duplicate key
        { 2627, 409 }
    };

    [Theory]
    [MemberData(nameof(ErrorCodeMappings))]
    public async Task SqlError_Number_MapsToExpectedStatus(int sqlNumber, int expectedStatus)
    {
        var middleware = new ErrorHandlingMiddleware(
            _ => throw BuildSqlException(sqlNumber),
            _mockLogger.Object);

        var context = new DefaultHttpContext();
        context.Request.Path = "/api/admin/test";

        await middleware.InvokeAsync(context);

        context.Response.StatusCode.Should().Be(expectedStatus);
        context.Response.ContentType.Should().Be("application/problem+json");
    }

    /// <summary>
    /// Builds a SqlException carrying the requested error number.
    /// Uses internal constructors of Microsoft.Data.SqlClient 7.0.2:
    /// SqlError(int, byte, byte, string, string, string, int, int, Exception, int),
    /// SqlErrorCollection.Add(SqlError), SqlException(string, SqlErrorCollection, Exception, Guid).
    /// </summary>
    private static SqlException BuildSqlException(int number)
    {
        const string message = "Test database error.";

        var errorCtor = typeof(SqlError).GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic)
            .OrderByDescending(c => c.GetParameters().Length)
            .First();
        var error = errorCtor.Invoke(new object?[]
        {
            number, (byte)1, (byte)16, "test-srv", message, "test-sp", 1, 0, null, 0
        });

        var collection = (SqlErrorCollection)Activator.CreateInstance(typeof(SqlErrorCollection), nonPublic: true)!;
        var add = typeof(SqlErrorCollection).GetMethods(BindingFlags.Instance | BindingFlags.NonPublic)
            .First(m => m.Name == "Add");
        add.Invoke(collection, new[] { error });

        var exCtor = typeof(SqlException).GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic)
            .First(c => c.GetParameters().Any(p => p.ParameterType == typeof(SqlErrorCollection)));
        return (SqlException)exCtor.Invoke(new object?[] { message, collection, null, Guid.NewGuid() });
    }
}