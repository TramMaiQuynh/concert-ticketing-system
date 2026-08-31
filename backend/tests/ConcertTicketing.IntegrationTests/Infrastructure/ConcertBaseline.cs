namespace ConcertTicketing.IntegrationTests.Infrastructure;

/// <summary>
/// Baseline dữ liệu của một concert OnSale sẵn sàng cho booking/payment/checkin.
/// Mỗi instance tạo qua <see cref="TestDataSeeder"/> → dữ liệu duy nhất cho test.
/// </summary>
public sealed class ConcertBaseline
{
    public required int AdminUserId { get; init; }
    public required int OrganizerUserId { get; init; }
    public required int CustomerUserId { get; init; }
    public required int ArtistId { get; init; }
    public required int VenueId { get; init; }
    public required int ZoneId { get; init; }
    public required int SeatId1 { get; init; }
    public required int SeatId2 { get; init; }
    public required int ConcertId { get; init; }
    public required int CategoryId { get; init; }
    public required int EventSeatId1 { get; init; }
    public required int EventSeatId2 { get; init; }
}

/// <summary>
/// Factory dựng baseline concert OnSale (admin SQL) từ seeder — dùng chung cho các
/// test integration về booking/payment/checkin.
/// </summary>
public static class ConcertBaselineFactory
{
    public static async Task<ConcertBaseline> CreateOnSaleAsync(
        TestDataSeeder seeder,
        bool waitlistEnabled = false,
        bool fairAccess = false,
        int purchaseLimit = 4)
    {
        var admin = await seeder.CreateUserAsync("Admin");
        var organizer = await seeder.CreateUserAsync("Organizer");
        var customer = await seeder.CreateUserAsync("Customer");

        var artist = await seeder.CreateArtistAsync();
        var venue = await seeder.CreateVenueAsync();
        var zone = await seeder.CreateZoneAsync(venue);
        var seat1 = await seeder.CreateSeatAsync(venue, zone, index: 1);
        var seat2 = await seeder.CreateSeatAsync(venue, zone, index: 2);

        var concertId = await seeder.CreateConcertDraftAsync(
            organizer, artist, venue, waitlistEnabled, fairAccess, purchaseLimit);
        var category = await seeder.CreateTicketCategoryAsync(concertId);
        var es1 = await seeder.CreateEventSeatAsync(concertId, seat1, category, price: 100000);
        var es2 = await seeder.CreateEventSeatAsync(concertId, seat2, category, price: 150000);

        await seeder.SetConcertOnSaleAsync(concertId);

        return new ConcertBaseline
        {
            AdminUserId = admin,
            OrganizerUserId = organizer,
            CustomerUserId = customer,
            ArtistId = artist,
            VenueId = venue,
            ZoneId = zone,
            SeatId1 = seat1,
            SeatId2 = seat2,
            ConcertId = concertId,
            CategoryId = category,
            EventSeatId1 = es1,
            EventSeatId2 = es2,
        };
    }
}