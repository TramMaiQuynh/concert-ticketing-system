using System.ComponentModel.DataAnnotations;

namespace ConcertTicketing.Application.DTOs;

// Stable keyset pagination: each response has at most Limit rows, ordered by ID.
public record AdminCatalogQuery(
    [Range(0, int.MaxValue)] int AfterId = 0,
    [Range(1, 200)] int Limit = 200,
    [Range(1, int.MaxValue)] int? VenueId = null,
    [Range(1, int.MaxValue)] int? ZoneId = null,
    [Range(1, int.MaxValue)] int? ConcertId = null,
    [Range(1, int.MaxValue)] int? PromotionId = null);

public record AdminConcertListItem(
    int ConcertID,
    string ConcertName,
    int VenueID,
    string ConcertStatus);

/// <summary>One artist assigned to a concert, in billing and display order.</summary>
public record ConcertArtistListItem(
    int ArtistID,
    string ArtistName,
    int ArtistOrder);

public record AdminZoneListItem(
    int ZoneID,
    int VenueID,
    string VenueName,
    string ZoneCode,
    string? ZoneName,
    string? ZoneDescription,
    string ZoneType,
    string ZoneStatus);

public record AdminSeatListItem(
    int SeatID,
    int ZoneID,
    int VenueID,
    string VenueName,
    string? ZoneName,
    string SeatCode,
    string? SeatLabel,
    string SeatStatus,
    string? SeatRowLabel,
    int? SeatColumnNumber);

public record AdminCategoryListItem(
    int TicketCategoryID,
    int ConcertID,
    string ConcertName,
    string CategoryName,
    string? CategoryDescription,
    decimal BasePrice,
    string CategoryStatus);

public record AdminPromotionListItem(
    int PromotionID,
    int ConcertID,
    string ConcertName,
    string PromotionName,
    string? PromotionDescription,
    string PromotionStatus,
    string DiscountType,
    decimal DiscountValue,
    DateTime StartDatetime,
    DateTime EndDatetime,
    bool CodeRequiredFlag);

public record AdminDiscountCodeListItem(
    int DiscountCodeID,
    int PromotionID,
    int ConcertID,
    string ConcertName,
    string PromotionName,
    string CodeValue,
    string CodeStatus,
    DateTime? ValidFromDatetime,
    DateTime? ValidToDatetime,
    int? GlobalUsageLimit,
    int? PerCustomerUsageLimit,
    int ReservedUsageCount,
    int ConsumedUsageCount);

public record AdminRefundListItem(
    int RefundID,
    int PaymentID,
    int BookingID,
    int ConcertID,
    string ConcertName,
    decimal RefundAmount,
    string RefundStatus,
    string? RefundReason,
    DateTime RefundRequestTimestamp,
    DateTime? RefundConfirmationTimestamp);
