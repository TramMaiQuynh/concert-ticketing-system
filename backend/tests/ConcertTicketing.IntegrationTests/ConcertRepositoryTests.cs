using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using FluentAssertions;

namespace ConcertTicketing.IntegrationTests;

/// <summary>
/// Integration tests cho ConcertRepository (connection API thật):
/// - GetListAsync: chỉ trả concert không phải Draft; filter theo trạng thái; phân trang
/// - GetByIdAsync: trả chi tiết đúng concert (artist, venue, status)
/// - GetSeatsAsync: trả đúng seat map với InventoryStatus + SalePrice
/// Đích: chứng minh query public của ConcertRepository chạy đúng với DB thật + least-privilege.
/// </summary>
public sealed class ConcertRepositoryTests : IClassFixture<DbFixture>
{
    private readonly DbFixture _fx;

    public ConcertRepositoryTests(DbFixture fx) => _fx = fx;

    private TestDataSeeder NewSeeder() => new(_fx);
    private ConcertRepository Repo() => new(_fx.ApiConnectionString);

    [Fact(DisplayName = "GetListAsync: concert OnSale xuất hiện; concert Draft không xuất hiện (public list)")]
    public async Task GetList_ExcludesDraft_IncludesOnSale()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        // Draft concert (chưa publish) — dùng lại chính baseline artist/venue/organizer
        // (CreateArtistAsync/CreateVenueAsync của seeder sinh tên CỐ ĐỊNH — không dùng
        // cho lần thứ hai vì sẽ trùng tên.)
        var draftConcertName = $"IT-Concert-{Guid.NewGuid():N}-draft-{_fx.Suffix}";
        var draftConcertId = await s.CreateConcertDraftAsync(
            baseline.OrganizerUserId, baseline.ArtistId, baseline.VenueId,
            concertName: draftConcertName);

        var list = (await Repo().GetListAsync(1, 1000, null)).ToList();

        list.Should().Contain(x => x.ConcertID == baseline.ConcertId && x.ConcertStatus == "OnSale");
        list.Any(x => x.ConcertID == draftConcertId).Should().BeFalse("Draft concerts không public");
    }

    [Fact(DisplayName = "GetListAsync: filter status=OnSale chỉ trả concert OnSale; phân trang hoạt động")]
    public async Task GetList_FilterStatus_And_Paging()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        var onSale = (await Repo().GetListAsync(1, 1000, "OnSale")).ToList();
        onSale.Select(x => x.ConcertStatus).Distinct().Should().AllBeEquivalentTo("OnSale");
        onSale.Should().Contain(x => x.ConcertID == baseline.ConcertId);

        // Trang 1 có dữ liệu; page=1 pageSize=1 trả tối đa 1 row
        var first = (await Repo().GetListAsync(1, 1, null)).ToList();
        first.Count.Should().BeLessThanOrEqualTo(1);
    }

    [Fact(DisplayName = "GetByIdAsync: trả đúng ConcertID + ArtistName + VenueName + ConcertStatus")]
    public async Task GetById_ReturnsDetail()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        var detail = await Repo().GetByIdAsync(baseline.ConcertId);

        detail.Should().NotBeNull();
        detail!.ConcertID.Should().Be(baseline.ConcertId);
        detail.ConcertName.Should().Be(s.ConcertName);
        detail.ConcertStatus.Should().Be("OnSale");
        detail.ArtistName.Should().NotBeNullOrEmpty();
        detail.VenueName.Should().NotBeNullOrEmpty();
        detail.PurchaseLimit.Should().Be(4);
    }

    [Fact(DisplayName = "GetByIdAsync: concert không tồn tại → null")]
    public async Task GetById_NotFound_ReturnsNull()
    {
        var detail = await Repo().GetByIdAsync(-999999);
        detail.Should().BeNull();
    }

    [Fact(DisplayName = "GetSeatsAsync: trả đúng seat map (InventoryStatus Available, SalePrice đúng)")]
    public async Task GetSeats_ReturnsSeatMap()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        var seats = (await Repo().GetSeatsAsync(baseline.ConcertId)).ToList();

        seats.Should().HaveCount(2);
        seats.Should().Contain(x => x.SeatID == baseline.EventSeatId1 && x.Price == 100000);
        seats.Should().Contain(x => x.SeatID == baseline.EventSeatId2 && x.Price == 150000);
        seats.Should().OnlyContain(x => x.InventoryStatus == "Available");
        seats.Should().OnlyContain(x => !string.IsNullOrEmpty(x.CategoryName));
    }
}