namespace ConcertTicketing.Domain.Models;

public class EventSeat
{
    public int SeatID { get; set; }
    public int ConcertID { get; set; }
    public string SeatNumber { get; set; } = string.Empty;
    public string? SectionName { get; set; }
    public string? Row { get; set; }
    public int SeatCategoryID { get; set; }
    public string InventoryStatus { get; set; } = string.Empty; // Available/OnHold/Sold/Reserved
    public decimal Price { get; set; }
}

public class SeatCategory
{
    public int SeatCategoryID { get; set; }
    public string CategoryName { get; set; } = string.Empty;
    public string? Description { get; set; }
}
