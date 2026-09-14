using ConcertTicketing.Application.DTOs;
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
    private ConcertRepository Repo() => new(_fx.ApiFactory);

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

    [Fact(DisplayName = "GetByIdAsync: concert Draft KHÔNG lộ ra endpoint public → null")]
    public async Task GetById_DraftConcert_ReturnsNull()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        var draftName = $"IT-Concert-{Guid.NewGuid():N}-draft-{_fx.Suffix}";
        var draftId = await s.CreateConcertDraftAsync(
            baseline.OrganizerUserId, baseline.ArtistId, baseline.VenueId, concertName: draftName);

        // GET /api/concerts/{id} là [AllowAnonymous]; concert chưa công bố không được lộ
        // tên, nghệ sĩ, địa điểm, cửa sổ bán hay giới hạn mua cho bất kỳ ai đoán được ID.
        var detail = await Repo().GetByIdAsync(draftId);
        detail.Should().BeNull("concert Draft không được hiển thị công khai");
    }

    [Fact(DisplayName = "GetSeatsAsync: concert Draft và Cancelled không lộ sơ đồ ghế")]
    public async Task GetSeats_DraftAndCancelled_ReturnsEmpty()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);

        // Draft: chưa công bố → không lộ sơ đồ ghế lẫn giá
        var draftName = $"IT-Concert-{Guid.NewGuid():N}-draft2-{_fx.Suffix}";
        var draftId = await s.CreateConcertDraftAsync(
            baseline.OrganizerUserId, baseline.ArtistId, baseline.VenueId, concertName: draftName);
        var draftCat = await s.CreateTicketCategoryAsync(draftId);
        // Dùng lại một Seat vật lý của baseline (cùng Venue nên thỏa TRG_EventSeatVenue);
        // một Seat được phép nằm trong kho vé của nhiều Concert — UNIQUE là (ConcertID, SeatID).
        await _fx.ExecAdminAsync(@"
            INSERT INTO EventSeat (ConcertID, SeatID, TicketCategoryID, InventoryStatus, SalePrice)
            SELECT @cid,
                   (SELECT TOP 1 SeatID FROM EventSeat WHERE ConcertID = @base ORDER BY EventSeatID),
                   tc.TicketCategoryID, 'Available', tc.BasePrice
            FROM   TicketCategory tc WHERE tc.TicketCategoryID = @cat;",
            new { cid = draftId, cat = draftCat, @base = baseline.ConcertId });

        (await Repo().GetSeatsAsync(draftId)).Should().BeEmpty("concert Draft không được lộ sơ đồ ghế");

        // Cancelled: BR50c — không tham gia luồng bán vé mới
        await _fx.ExecAdminAsync(
            "EXEC sp_UpdateConcertStatus @ConcertID=@cid, @ActorUserID=@adm, @NewStatus='Cancelled';",
            new { cid = baseline.ConcertId, adm = baseline.AdminUserId });

        (await Repo().GetSeatsAsync(baseline.ConcertId))
            .Should().BeEmpty("concert đã hủy không vào luồng bán vé mới (BR50c)");

        // Nhưng chi tiết concert đã hủy VẪN hiển thị — khách cần biết sự kiện bị hủy
        (await Repo().GetByIdAsync(baseline.ConcertId)).Should().NotBeNull();
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
        // BR10a: mọi ghế cùng hạng vé có giá bằng BasePrice của hạng đó (100000),
        // không còn đặt giá riêng từng ghế.
        seats.Should().Contain(x => x.SeatID == baseline.EventSeatId1 && x.Price == 100000);
        seats.Should().Contain(x => x.SeatID == baseline.EventSeatId2 && x.Price == 100000);
        seats.Should().OnlyContain(x => x.InventoryStatus == "Available");
        seats.Should().OnlyContain(x => !string.IsNullOrEmpty(x.CategoryName));
    }

    [Fact(DisplayName = "ListActivePromotionsAsync: trả promotion đang hiệu lực (VW_ActivePromotions)")]
    public async Task ListActivePromotions_ReturnsActiveOnes()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var adminRepo = new AdminRepository(_fx.ApiFactory);

        var promoId = await adminRepo.CreatePromotionAsync(baseline.AdminUserId, baseline.ConcertId,
            new CreatePromotionRequest(
                s.PromotionName, "Giảm 10% cho mọi vé", "PERCENTAGE", 10,
                DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1),
                UsageLimit: 100, CodeRequiredFlag: false));

        var promotions = (await Repo().ListActivePromotionsAsync(baseline.ConcertId)).ToList();

        promotions.Should().Contain(x => x.PromotionID == promoId
            && x.ConcertID == baseline.ConcertId
            && x.PromotionName == s.PromotionName);
    }

    [Fact(DisplayName = "ListActivePromotionsAsync: concert Draft không lộ khuyến mãi (endpoint AllowAnonymous)")]
    public async Task ListActivePromotions_DraftConcert_ReturnsEmpty()
    {
        var s = NewSeeder();
        var baseline = await ConcertBaselineFactory.CreateOnSaleAsync(s);
        var draftName = $"IT-Concert-{Guid.NewGuid():N}-draftpromo-{_fx.Suffix}";
        var draftId = await s.CreateConcertDraftAsync(
            baseline.OrganizerUserId, baseline.ArtistId, baseline.VenueId, concertName: draftName);

        var adminRepo = new AdminRepository(_fx.ApiFactory);
        await adminRepo.CreatePromotionAsync(baseline.AdminUserId, draftId,
            new CreatePromotionRequest(
                s.PromotionName + "-draft", "chưa công bố", "PERCENTAGE", 10,
                DateTime.UtcNow.AddDays(-1), DateTime.UtcNow.AddDays(1),
                UsageLimit: 100, CodeRequiredFlag: false));

        (await Repo().ListActivePromotionsAsync(draftId))
            .Should().BeEmpty("concert Draft chưa công bố không được lộ khuyến mãi ra endpoint công khai");
    }
}