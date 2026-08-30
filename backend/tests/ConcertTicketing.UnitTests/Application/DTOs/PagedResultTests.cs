using System.Collections.Generic;
using Xunit;
using FluentAssertions;
using ConcertTicketing.Application.DTOs;

namespace ConcertTicketing.UnitTests.Application.DTOs;

public class PagedResultTests
{
    [Fact]
    public void TotalPages_RoundsUp()
    {
        var items = new List<string>();
        var pagedResult = new PagedResult<string>(items, 11, 1, 5);

        pagedResult.TotalPages.Should().Be(3);
    }

    [Fact]
    public void TotalPages_ExactDivision()
    {
        var items = new List<string>();
        var pagedResult = new PagedResult<string>(items, 10, 1, 5);

        pagedResult.TotalPages.Should().Be(2);
    }
}
