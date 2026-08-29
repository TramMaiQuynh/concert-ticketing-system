namespace ConcertTicketing.Domain.Models;

public class Booking
{
    public int BookingID { get; set; }
    public int CustomerUserID { get; set; }
    public int ConcertID { get; set; }
    public string BookingStatus { get; set; } = string.Empty; // Pending/Confirmed/Cancelled/Expired
    public DateTime BookingDatetime { get; set; }
    public DateTime? HoldExpiryDatetime { get; set; }
    public decimal SubtotalAmount { get; set; }
    public decimal DiscountAmount { get; set; }
    public decimal FinalAmount { get; set; }
    public int? AppliedPromotionID { get; set; }
    public string? BookingReference { get; set; }
}
