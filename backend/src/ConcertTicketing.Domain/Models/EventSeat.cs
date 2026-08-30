namespace ConcertTicketing.Domain.Models;

public class EventSeat
{
    public int EventSeatID { get; set; }
    public int ConcertID { get; set; }
    public int SeatID { get; set; }
    public int TicketCategoryID { get; set; }
    public decimal SalePrice { get; set; }
    public string InventoryStatus { get; set; } = string.Empty; // Available/OnHold/Booked/OnHoldForWaitlist/Unavailable
    public DateTime AddedTimestamp { get; set; }
    public string? UnavailabilityReason { get; set; }
}

public class TicketCategory
{
    public int TicketCategoryID { get; set; }
    public int ConcertID { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public string CategoryStatus { get; set; } = string.Empty;
}
