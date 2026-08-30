namespace ConcertTicketing.Domain.Models;

public class Concert
{
    public int ConcertID { get; set; }
    public int OrganizerUserID { get; set; }
    public int ArtistID { get; set; }
    public int VenueID { get; set; }
    public string ConcertName { get; set; } = string.Empty;
    public DateTime StartDatetime { get; set; }
    public DateTime? EndDatetime { get; set; }
    public string ConcertStatus { get; set; } = string.Empty; // Draft/Published/OnSale/Completed/Cancelled
    public DateTime? SaleStartDatetime { get; set; }
    public DateTime? SaleEndDatetime { get; set; }
    public int? PurchaseLimit { get; set; }
    public int? TemporaryHoldDuration { get; set; }
    public bool FairAccessEnabled { get; set; }
    public bool WaitlistEnabled { get; set; }
    public bool SalesPaused { get; set; }
    public string? CancellationPolicy { get; set; }
    public string? RefundPolicy { get; set; }
}
