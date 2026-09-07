-- Đã xóa chỉ mục IX_BookingAllocation_Concert_EventSeat do cột ConcertID không tồn tại trên bảng BookingEventSeatAllocation.
-- Chi tiết sửa đổi đã được cập nhật tại plan.txt §23.2.

-- (EventSeatID) có WHERE TicketStatus='Issued' trên Ticket
CREATE UNIQUE NONCLUSTERED INDEX UIX_Ticket_Issued_EventSeat 
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

-- ============================================================
-- AuditRecord (BP15 / FR59 / BO10)
-- ============================================================
-- Bang nay chi duoc GHI THEM: TRG_AuditLog chan moi UPDATE/DELETE, nen chi phi bao tri
-- index chi den tu INSERT - khong co page split do update, khong co xoa. Doi lai, moi
-- thao tac nghiep vu deu ghi it nhat mot dong vao day, vi vay chi tao index cho nhung
-- CAU HOI CO THAT, khong tao du phong.
--
-- Truoc day bang khong co index nao ngoai PK cum tren AuditID. Moi truy van nghiep vu
-- deu la quet toan bang - trong khi day chinh la bang lon nhanh nhat he thong.
--
-- CO Y KHONG dung INCLUDE cho PreviousValue/NewValue: hai cot do la NVARCHAR(MAX),
-- dua vao index se nhan ban toan bo noi dung JSON sang moi index va lam bang index
-- phinh gan bang bang du lieu. Chap nhan key lookup - dung danh doi o day.

-- (1) Cau hoi chinh cua audit: "lich su cua thuc the nay". EventTimestamp nam trong
--     khoa de vua loc vua sap xep theo thoi gian ma khong can sort.
CREATE NONCLUSTERED INDEX IX_AuditRecord_Entity
ON AuditRecord (EntityType, EntityID, EventTimestamp);

-- (2) Truy van theo khoang thoi gian / hoat dong gan day (VW_AuditTrail khong loc
--     thuong duyet theo thoi gian).
CREATE NONCLUSTERED INDEX IX_AuditRecord_Timestamp
ON AuditRecord (EventTimestamp);

-- (3) "Nguoi dung nay da lam gi" - dieu tra quyen han theo BR52/FR59.
CREATE NONCLUSTERED INDEX IX_AuditRecord_Actor
ON AuditRecord (ActorUserID, EventTimestamp);

-- (4) Gom cac dong ghi trong CUNG mot giao dich nghiep vu (sp_ConfirmPayment ghi 3 dong,
--     sp_UpdateConcertStatus ghi cascade - tat ca chung mot TransactionReference). Do
--     chinh la ly do cot nay ton tai; khong co index thi viec gom lai phai quet bang.
--     Filtered vi cot thua NULL - chi cac SP dung TxnRef moi ghi.
CREATE NONCLUSTERED INDEX IX_AuditRecord_TransactionRef
ON AuditRecord (TransactionReference)
WHERE TransactionReference IS NOT NULL;
