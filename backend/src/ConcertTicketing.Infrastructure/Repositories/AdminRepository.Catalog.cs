using Dapper;
using ConcertTicketing.Application.DTOs;

namespace ConcertTicketing.Infrastructure.Repositories;

public partial class AdminRepository
{
    public async Task<IEnumerable<AdminConcertListItem>> ListConcertsAsync(AdminCatalogQuery query)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AdminConcertListItem>(@"
            SELECT TOP (@Limit) ConcertID, ConcertName, VenueID, ConcertStatus
            FROM dbo.VW_AdminConcerts
            WHERE ConcertID > @AfterId AND (@ConcertId IS NULL OR ConcertID = @ConcertId)
            ORDER BY ConcertID;",
            query with { Limit = Math.Clamp(query.Limit, 1, 200) });
    }

    public async Task<IEnumerable<ConcertArtistListItem>> ListConcertArtistsAsync(int concertId)
    {
        using var conn = await _factory.OpenAsync();
        // Scope through VW_AdminConcerts. The view derives identity from
        // SESSION_CONTEXT, so an Organizer cannot probe another Organizer's
        // concert by changing a route parameter.
        return await conn.QueryAsync<ConcertArtistListItem>(@"
            SELECT ca.ArtistID, a.ArtistName, ca.ArtistOrder
            FROM dbo.ConcertArtist ca
            JOIN dbo.VW_AdminConcerts c ON c.ConcertID = ca.ConcertID
            JOIN dbo.Artist a ON a.ArtistID = ca.ArtistID
            WHERE ca.ConcertID = @concertId
            ORDER BY ca.ArtistOrder;", new { concertId });
    }

    public async Task<IEnumerable<AdminZoneListItem>> ListZonesAsync(AdminCatalogQuery query)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AdminZoneListItem>(@"
            SELECT TOP (@Limit) z.ZoneID, z.VenueID, v.VenueName, z.ZoneCode, z.ZoneName, z.ZoneDescription, z.ZoneType, z.ZoneStatus
            FROM dbo.Zone z JOIN dbo.Venue v ON v.VenueID = z.VenueID
            WHERE z.ZoneID > @AfterId AND (@VenueId IS NULL OR z.VenueID = @VenueId)
            ORDER BY z.ZoneID;",
            query with { Limit = Math.Clamp(query.Limit, 1, 200) });
    }

    public async Task<IEnumerable<AdminSeatListItem>> ListSeatsAsync(AdminCatalogQuery query)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AdminSeatListItem>(@"
            SELECT TOP (@Limit) s.SeatID, s.ZoneID, s.VenueID, v.VenueName, z.ZoneName, s.SeatCode, s.SeatLabel, s.SeatStatus, s.SeatRowLabel, s.SeatColumnNumber
            FROM dbo.Seat s JOIN dbo.Zone z ON z.ZoneID = s.ZoneID JOIN dbo.Venue v ON v.VenueID = s.VenueID
            WHERE s.SeatID > @AfterId AND (@VenueId IS NULL OR s.VenueID = @VenueId) AND (@ZoneId IS NULL OR s.ZoneID = @ZoneId)
            ORDER BY s.SeatID;",
            query with { Limit = Math.Clamp(query.Limit, 1, 200) });
    }

    public async Task<IEnumerable<AdminCategoryListItem>> ListCategoriesAsync(AdminCatalogQuery query)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AdminCategoryListItem>(@"
            SELECT TOP (@Limit) TicketCategoryID, ConcertID, ConcertName, CategoryName, CategoryDescription, BasePrice, CategoryStatus
            FROM dbo.VW_AdminCategories
            WHERE TicketCategoryID > @AfterId AND (@ConcertId IS NULL OR ConcertID = @ConcertId)
            ORDER BY TicketCategoryID;",
            query with { Limit = Math.Clamp(query.Limit, 1, 200) });
    }

    public async Task<IEnumerable<AdminPromotionListItem>> ListPromotionsAsync(AdminCatalogQuery query)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AdminPromotionListItem>(@"
            SELECT TOP (@Limit) PromotionID, ConcertID, ConcertName, PromotionName, PromotionDescription, PromotionStatus, DiscountType, DiscountValue, StartDatetime, EndDatetime, CodeRequiredFlag
            FROM dbo.VW_AdminPromotions
            WHERE PromotionID > @AfterId AND (@ConcertId IS NULL OR ConcertID = @ConcertId)
            ORDER BY PromotionID;",
            query with { Limit = Math.Clamp(query.Limit, 1, 200) });
    }

    public async Task<IEnumerable<AdminDiscountCodeListItem>> ListDiscountCodesAsync(AdminCatalogQuery query)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AdminDiscountCodeListItem>(@"
            SELECT TOP (@Limit) DiscountCodeID, PromotionID, ConcertID, ConcertName, PromotionName, CodeValue, CodeStatus, ValidFromDatetime, ValidToDatetime, GlobalUsageLimit, PerCustomerUsageLimit, ReservedUsageCount, ConsumedUsageCount
            FROM dbo.VW_AdminDiscountCodes
            WHERE DiscountCodeID > @AfterId AND (@ConcertId IS NULL OR ConcertID = @ConcertId) AND (@PromotionId IS NULL OR PromotionID = @PromotionId)
            ORDER BY DiscountCodeID;",
            query with { Limit = Math.Clamp(query.Limit, 1, 200) });
    }

    public async Task<IEnumerable<AdminRefundListItem>> ListRefundsAsync(AdminCatalogQuery query)
    {
        using var conn = await _factory.OpenAsync();
        return await conn.QueryAsync<AdminRefundListItem>(@"
            SELECT TOP (@Limit) RefundID, PaymentID, BookingID, ConcertID, ConcertName, RefundAmount, RefundStatus, RefundReason, RefundRequestTimestamp, RefundConfirmationTimestamp
            FROM dbo.VW_AdminRefunds
            WHERE RefundID > @AfterId AND (@ConcertId IS NULL OR ConcertID = @ConcertId)
            ORDER BY RefundID;",
            query with { Limit = Math.Clamp(query.Limit, 1, 200) });
    }

}
