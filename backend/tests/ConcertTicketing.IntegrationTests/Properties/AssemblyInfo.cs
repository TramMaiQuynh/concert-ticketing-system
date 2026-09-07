using Xunit;

// Integration tests chạy trên CÙNG một live database (ConcertTicketingDB).
// Nếu để xUnit chạy parallel theo class, các class test sẽ đồng thời INSERT/DELETE
// trên cùng các bảng → deadlock (đã quan sát thấy trong thực tế). Do đó phải
// tuần tự hóa toàn bộ test collections trong project này.
[assembly: CollectionBehavior(DisableTestParallelization = true)]