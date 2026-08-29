-- Đã xóa chỉ mục IX_BookingAllocation_Concert_EventSeat do cột ConcertID không tồn tại trên bảng BookingEventSeatAllocation.
-- Chi tiết sửa đổi đã được cập nhật tại plan.txt §23.2.

-- (EventSeatID) có WHERE TicketStatus='Issued' trên Ticket
CREATE NONCLUSTERED INDEX IX_Ticket_Issued_EventSeat 
ON Ticket (EventSeatID)
WHERE TicketStatus = 'Issued';

-- (BookingID) trên Payment
CREATE NONCLUSTERED INDEX IX_Payment_Booking 
ON Payment (BookingID);

-- (ConcertID) trên Ticket/Check-in để truy vấn theo Concert (BO9/FR55)
CREATE NONCLUSTERED INDEX IX_Ticket_Concert ON Ticket (ConcertID);
CREATE NONCLUSTERED INDEX IX_CheckIn_Concert ON CheckIn (ConcertID);

-- Reporting Indexes
CREATE NONCLUSTERED INDEX IX_Booking_Concert_Status ON Booking (ConcertID, BookingStatus);
CREATE NONCLUSTERED INDEX IX_Ticket_Concert_Status ON Ticket (ConcertID, TicketStatus);
CREATE NONCLUSTERED INDEX IX_CheckIn_Concert_Timestamp ON CheckIn (ConcertID, CheckInTimestamp);
CREATE NONCLUSTERED INDEX IX_Payment_Status_Timestamp ON Payment (PaymentStatus, ConfirmationTimestamp);
CREATE NONCLUSTERED INDEX IX_WaitlistEntry_Waitlist_Status_Joined ON WaitlistEntry (WaitlistID, EntryStatus, JoinedTimestamp);
CREATE NONCLUSTERED INDEX IX_QueueEntry_Queue_Status ON QueueEntry (QueueID, QueueStatus);

-- Optimized covering index for iTVF (fn_GetCustomerTicketCount)
CREATE NONCLUSTERED INDEX IX_Booking_Customer_Concert_Status 
ON Booking (CustomerUserID, ConcertID, BookingStatus);
