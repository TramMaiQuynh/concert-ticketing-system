using ConcertTicketing.Application.DTOs;
using ConcertTicketing.Infrastructure.Repositories;
using ConcertTicketing.IntegrationTests.Infrastructure;
using Dapper;
using FluentAssertions;

namespace ConcertTicketing.IntegrationTests;

public sealed class AdminCatalogRepositoryTests(DbFixture fx) : IClassFixture<DbFixture>
{
    private AdminRepository As(int userId) => new(fx.ApiFactory.AsUser(userId));

    [Fact]
    public async Task OwnedCatalogs_IncludeDraftsAndInactiveRows_AndDenyOtherIdentities()
    {
        var seed = new TestDataSeeder(fx);
        var b = await ConcertBaselineFactory.CreateOnSaleAsync(seed);
        var owner = As(b.OrganizerUserId);
        var draft = await seed.CreateConcertDraftAsync(b.OrganizerUserId, b.ArtistId, b.VenueId,
            concertName: seed.ConcertName + "-Draft");
        var category = await owner.ConfigureTicketCategoryAsync(b.OrganizerUserId, draft,
            new ConfigureTicketCategoryRequest("Inactive category", null, 120000, CategoryStatus: "Inactive"));
        var promotion = await owner.CreatePromotionAsync(b.OrganizerUserId, draft,
            new CreatePromotionRequest("Private promotion", null, "Fixed Amount", 10000,
                DateTime.Now.AddDays(-1), DateTime.Now.AddDays(2), CodeRequiredFlag: true));
        var code = await owner.CreateDiscountCodeAsync(b.OrganizerUserId, promotion,
            new CreateDiscountCodeRequest(seed.DiscountCodeValue));
        await owner.UpdateDiscountCodeStatusAsync(b.OrganizerUserId, code, "Disabled");

        var booking = await new BookingRepository(fx.ApiFactory).CreateAsync(b.CustomerUserId,
            new CreateBookingRequest(b.ConcertId, [b.EventSeatId1]));
        var payments = new PaymentRepository(fx.ApiFactory, fx.PaymentSignatureSecret, DbFixture.TestGateway);
        var payment = await payments.InitiateAsync(booking.BookingId, b.CustomerUserId);
        await payments.ConfirmAsync(booking.BookingId, payment.PaymentId,
            fx.ComputePaymentSignature(booking.BookingId, payment.PaymentId, payment.Amount), "CATALOG-TEST");
        var refund = await payments.ProcessRefundAsync(booking.BookingId, "Catalog test", b.AdminUserId);
        refund.Should().BeGreaterThan(0);

        foreach (var user in new[] { b.OrganizerUserId, b.AdminUserId })
        {
            var repo = As(user);
            (await repo.ListConcertsAsync(new(AfterId: draft - 1))).Should()
                .Contain(x => x.ConcertID == draft && x.ConcertStatus == "Draft");
            (await repo.ListConcertArtistsAsync(draft)).Should()
                .ContainSingle(x => x.ArtistID == b.ArtistId && x.ArtistOrder == 1);
            (await repo.ListCategoriesAsync(new(ConcertId: draft))).Should()
                .ContainSingle(x => x.TicketCategoryID == category && x.CategoryStatus == "Inactive");
            (await repo.ListPromotionsAsync(new(ConcertId: draft))).Should()
                .ContainSingle(x => x.PromotionID == promotion && x.PromotionStatus == "Active");
            (await repo.ListDiscountCodesAsync(new(PromotionId: promotion))).Should()
                .ContainSingle(x => x.DiscountCodeID == code && x.CodeStatus == "Disabled"
                    && x.CodeValue == seed.DiscountCodeValue && x.ConcertID == draft);
            (await repo.ListRefundsAsync(new(ConcertId: b.ConcertId))).Should()
                .ContainSingle(x => x.RefundID == refund && x.BookingID == booking.BookingId
                    && x.RefundStatus == "Pending" && x.RefundAmount > 0);
        }

        var stranger = await seed.CreateUserAsync("Organizer", instance: 9);
        foreach (var repo in new[] { As(stranger), As(b.CustomerUserId), new AdminRepository(fx.ApiFactory) })
        {
            // With and without explicit parent IDs: a filter cannot expand visibility.
            (await repo.ListConcertsAsync(new())).Should().BeEmpty();
            (await repo.ListConcertArtistsAsync(draft)).Should().BeEmpty();
            (await repo.ListCategoriesAsync(new())).Should().BeEmpty();
            (await repo.ListCategoriesAsync(new(ConcertId: draft))).Should().BeEmpty();
            (await repo.ListPromotionsAsync(new())).Should().BeEmpty();
            (await repo.ListPromotionsAsync(new(ConcertId: draft))).Should().BeEmpty();
            (await repo.ListDiscountCodesAsync(new())).Should().BeEmpty();
            (await repo.ListDiscountCodesAsync(new(PromotionId: promotion))).Should().BeEmpty();
            (await repo.ListRefundsAsync(new())).Should().BeEmpty();
            (await repo.ListRefundsAsync(new(ConcertId: b.ConcertId))).Should().BeEmpty();
        }
        (await owner.ListDiscountCodesAsync(new(ConcertId: b.ConcertId, PromotionId: promotion)))
            .Should().BeEmpty("parent filters must intersect");

        await As(b.AdminUserId).UpdateUserStatusAsync(b.AdminUserId, b.OrganizerUserId, new("Locked"));
        (await owner.ListConcertsAsync(new())).Should().BeEmpty("locked accounts cannot use a stale JWT to read");
        (await owner.ListDiscountCodesAsync(new())).Should().BeEmpty();
        (await owner.ListRefundsAsync(new())).Should().BeEmpty();
        await As(b.AdminUserId).UpdateUserStatusAsync(b.AdminUserId, b.OrganizerUserId, new("Active"));
        await As(b.AdminUserId).AssignRoleAsync(b.AdminUserId,
            new AssignRoleRequest(b.OrganizerUserId, "Organizer", "Revoke"));
        (await owner.ListConcertsAsync(new())).Should().BeEmpty("revoked owners lose read access immediately");
        (await owner.ListDiscountCodesAsync(new())).Should().BeEmpty();
        (await owner.ListRefundsAsync(new())).Should().BeEmpty();
    }

    [Fact]
    public async Task SharedCatalogs_RespectParentFilters_AndPaginationDoesNotSkipRows()
    {
        var seed = new TestDataSeeder(fx);
        var b = await ConcertBaselineFactory.CreateOnSaleAsync(seed);
        var repo = As(b.OrganizerUserId);
        (await repo.ListZonesAsync(new(VenueId: b.VenueId))).Should()
            .ContainSingle(x => x.ZoneID == b.ZoneId && x.VenueID == b.VenueId);
        var first = (await repo.ListSeatsAsync(new(Limit: 1, VenueId: b.VenueId))).Single();
        var second = (await repo.ListSeatsAsync(new(AfterId: first.SeatID, Limit: 1, VenueId: b.VenueId))).Single();
        new[] { first.SeatID, second.SeatID }.Should().Equal(b.SeatId1, b.SeatId2);
        (await repo.ListSeatsAsync(new(AfterId: second.SeatID, VenueId: b.VenueId))).Should().BeEmpty();
        (await repo.ListSeatsAsync(new(VenueId: int.MaxValue, ZoneId: b.ZoneId))).Should().BeEmpty();
        (await repo.ListSeatsAsync(new(Limit: int.MaxValue))).Count().Should().BeLessThanOrEqualTo(200);

        // Check the scoped view using the actual organizer SQL principal too:
        // ownership chaining must work while base DiscountCode SELECT stays denied.
        await using var conn = new Microsoft.Data.SqlClient.SqlConnection(fx.AdminConnectionString);
        await conn.OpenAsync();
        await conn.ExecuteAsync("EXEC sp_set_session_context @key=N'UserID', @value=@id;",
            new { id = b.OrganizerUserId });
        await conn.ExecuteAsync("EXECUTE AS USER = 'app_organizer';");
        try
        {
            (await conn.QueryAsync<int>("SELECT ConcertID FROM dbo.VW_AdminConcerts;"))
                .Should().Contain(b.ConcertId);
            await conn.QueryAsync<int>("SELECT DiscountCodeID FROM dbo.VW_AdminDiscountCodes;");
            var denied = () => conn.QueryAsync<int>("SELECT DiscountCodeID FROM dbo.DiscountCode;");
            await denied.Should().ThrowAsync<Microsoft.Data.SqlClient.SqlException>();
        }
        finally { await conn.ExecuteAsync("REVERT;"); }
    }
}
