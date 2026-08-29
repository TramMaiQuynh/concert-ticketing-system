namespace ConcertTicketing.Domain.Models;

public class Concert
{
    public int ConcertID { get; set; }
    public string ConcertName { get; set; } = string.Empty;
    public int ArtistID { get; set; }
    public int VenueID { get; set; }
    public DateTime ConcertDate { get; set; }
    public string Status { get; set; } = string.Empty;   // Draft/Published/OnSale/Completed/Cancelled
    public bool SalesPaused { get; set; }
    public DateTime? SaleStartDatetime { get; set; }
    public DateTime? SaleEndDatetime { get; set; }
    public int? PurchaseLimitPerCustomer { get; set; }
    public string? Description { get; set; }
    public string? ImageUrl { get; set; }
}
