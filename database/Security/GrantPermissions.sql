-- ============================================================
-- GrantPermissions.sql
-- Phan quyen GRANT / DENY theo tung vai tro (BR37-BR39 / §23.7).
-- Nguyen tac: khong cap quyen ghi truc tiep vao bang;
-- moi thao tac nghiep vu phai qua Stored Procedure.
-- ============================================================

-- ============================================================
-- 1. app_admin: Toan quyen tren tat ca cac doi tuong
-- ============================================================
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::dbo TO app_admin;
GRANT EXECUTE ON SCHEMA::dbo TO app_admin;

-- ============================================================
-- 2. app_organizer: Quan ly Concert thuoc so huu; xem bao cao
--    - KHONG duoc INSERT/UPDATE truc tiep vao bang
--    - Moi thao tac qua Stored Procedure
-- ============================================================

-- Quyen xem du lieu cong khai
GRANT SELECT ON dbo.Concert              TO app_organizer;
GRANT SELECT ON dbo.Venue                TO app_organizer;
GRANT SELECT ON dbo.Zone                 TO app_organizer;
GRANT SELECT ON dbo.Seat                 TO app_organizer;
GRANT SELECT ON dbo.Artist               TO app_organizer;
GRANT SELECT ON dbo.EventSeat            TO app_organizer;
GRANT SELECT ON dbo.TicketCategory       TO app_organizer;
-- Quyen xem du lieu qua RLS View (CRIT-20)
GRANT SELECT ON dbo.VW_OrganizerBooking  TO app_organizer;
GRANT SELECT ON dbo.VW_OrganizerPayment  TO app_organizer;
GRANT SELECT ON dbo.VW_OrganizerTicket   TO app_organizer;
GRANT SELECT ON dbo.VW_ConcertAttendeeList TO app_organizer;

-- KHONG doc truc tiep bang giao dich
DENY SELECT ON dbo.Booking TO app_organizer;
DENY SELECT ON dbo.Payment TO app_organizer;
DENY SELECT ON dbo.Ticket TO app_organizer;
GRANT SELECT ON dbo.Promotion            TO app_organizer;
GRANT SELECT ON dbo.CheckIn              TO app_organizer;
GRANT SELECT ON dbo.Waitlist             TO app_organizer;
GRANT SELECT ON dbo.WaitlistEntry        TO app_organizer;

-- KHONG cap SELECT tren DiscountCode cho app_organizer.
-- Bang nay chua CodeValue cua MOI Promotion cua MOI Organizer, khong co cot nao
-- gioi han pham vi, nen mot Organizer se doc va su dung duoc ma giam gia chua cong
-- bo cua doi thu. Day cung la ly do app_customer bi DENY o muc duoi. Organizer thao
-- tac tren ma cua chinh minh qua sp_CreateDiscountCode / sp_UpdateDiscountCodeStatus
-- (hai SP nay tu kiem tra quyen so huu Concert).
DENY SELECT ON dbo.DiscountCode          TO app_organizer;

-- Quyen xem Views bao cao.
-- Bon view nay deu da duoc gioi han pham vi bang SESSION_CONTEXT(N'UserID')
-- (Organizer chi thay Concert cua minh, Admin thay toan bo - §23.9), nen quyen
-- SELECT o day khong con dong nghia voi doc du lieu cua Organizer khac.
-- Dieu kien tien quyet: tang ung dung PHAI dat session context sau khi mo connection.
GRANT SELECT ON dbo.VW_ConcertSalesSummary   TO app_organizer;
GRANT SELECT ON dbo.VW_ActiveInventoryStatus TO app_organizer;
GRANT SELECT ON dbo.VW_CheckInReport         TO app_organizer;
GRANT SELECT ON dbo.VW_WaitlistQueue         TO app_organizer;

-- Quyen thuc thi Stored Procedures lien quan
GRANT EXECUTE ON dbo.sp_ProcessRefund        TO app_organizer;
GRANT EXECUTE ON dbo.sp_UpdateRefundStatus   TO app_organizer;  -- Pending->Failed/Cancelled (§10.1/§24.4/BR32)
GRANT EXECUTE ON dbo.sp_ApplyPromotion  TO app_organizer;
-- Cau hinh Fair Access / Waitlist va vong doi khuyen mai cho Concert cua chinh minh
-- (moi SP tu kiem tra Concert.OrganizerUserID = @ActorUserID hoac Admin).
GRANT EXECUTE ON dbo.sp_ConfigureQueue            TO app_organizer;
GRANT EXECUTE ON dbo.sp_ConfigureWaitlist         TO app_organizer;
GRANT EXECUTE ON dbo.sp_UpdatePromotionStatus     TO app_organizer;
GRANT EXECUTE ON dbo.sp_UpdateDiscountCodeStatus  TO app_organizer;
-- Phan cong nhan vien soat ve (BR39/FR51) cho Concert cua chinh minh. Viec CAP Role
-- 'Check-in Staff' van chi Admin (sp_AssignRole) - day chi la buoc xep ca lam viec
-- cho nguoi da duoc cap Role, nen SP tu kiem tra Concert.OrganizerUserID.
GRANT EXECUTE ON dbo.sp_AddCheckinStaffAssignment TO app_organizer;

-- Chặn truy cap AuditRecord truc tiep (chi Admin duoc doc)
DENY SELECT ON dbo.AuditRecord TO app_organizer;

-- ============================================================
-- 3. app_customer: Chi duoc thao tac tren du lieu cua chinh minh
--    Moi thao tac nghiep vu qua Stored Procedure
-- ============================================================

-- Quyen xem du lieu cong khai (tim Concert)
GRANT SELECT ON dbo.Concert          TO app_customer;
GRANT SELECT ON dbo.Venue            TO app_customer;
GRANT SELECT ON dbo.Artist           TO app_customer;
GRANT SELECT ON dbo.EventSeat        TO app_customer;
GRANT SELECT ON dbo.TicketCategory   TO app_customer;
GRANT SELECT ON dbo.VW_ActivePromotions TO app_customer;

-- Chan doc bang khuyen mai goc
DENY SELECT ON dbo.Promotion TO app_customer;
DENY SELECT ON dbo.DiscountCode TO app_customer;

-- Quyen xem lich su cua chinh minh qua View
GRANT SELECT ON dbo.VW_CustomerBookingHistory TO app_customer;

-- Quyen thuc thi Stored Procedures
GRANT EXECUTE ON dbo.sp_CreateBooking   TO app_customer;
GRANT EXECUTE ON dbo.sp_ApplyPromotion  TO app_customer;
GRANT EXECUTE ON dbo.sp_ProcessRefund   TO app_customer;

-- Chan app_customer doc truc tiep bang Booking/Payment/Ticket
-- (phai dung View hoac SP de loc dung CustomerUserID)
DENY SELECT ON dbo.Booking  TO app_customer;
DENY SELECT ON dbo.Payment  TO app_customer;
DENY SELECT ON dbo.Ticket   TO app_customer;
DENY SELECT ON dbo.AuditRecord TO app_customer;
DENY SELECT ON dbo.UserAccount TO app_customer;

-- ============================================================
-- 4. app_checkinstaff: Chi duoc xac thuc Ticket va xem thong tin
--    kiem tra, trong pham vi Concert duoc phan cong (BR39)
-- ============================================================

-- Quyen xem thong tin can thiet de check-in
GRANT SELECT ON dbo.Ticket                  TO app_checkinstaff;
GRANT SELECT ON dbo.Concert                 TO app_checkinstaff;
GRANT SELECT ON dbo.CheckinStaffAssignment  TO app_checkinstaff;
GRANT SELECT ON dbo.CheckIn                 TO app_checkinstaff;
GRANT SELECT ON dbo.VW_CheckInStaffUserAccount TO app_checkinstaff;
GRANT SELECT ON dbo.VW_CheckInReport        TO app_checkinstaff;

-- Quyen thuc thi SP check-in
GRANT EXECUTE ON dbo.sp_CheckInTicket TO app_checkinstaff;

-- Chan doc bang UserAccount goc
DENY SELECT ON dbo.UserAccount TO app_checkinstaff;

-- Chan moi quyen ghi truc tiep khac
DENY INSERT, UPDATE, DELETE ON dbo.Ticket       TO app_checkinstaff;
DENY INSERT, UPDATE, DELETE ON dbo.Booking      TO app_checkinstaff;
DENY SELECT  ON dbo.AuditRecord                 TO app_checkinstaff;
DENY SELECT  ON dbo.Payment                     TO app_checkinstaff;

-- ============================================================
-- 5. api_service: Backend API Service Account
--    Nguyen tac: chi EXECUTE SP + SELECT bang read-only.
--    KHONG DUOC INSERT/UPDATE/DELETE truc tiep vao bang
--    (ngoai tru RefreshToken).
-- ============================================================

-- 1. Quyen Thuc thi tat ca Stored Procedures (Bao gom 3 SP moi)
GRANT EXECUTE ON SCHEMA::dbo TO api_service;

-- 2. Quyen Doc TRUC TIEP (Cho phep Dapper queries)
--    Chi cap SELECT tren nhung bang ma backend thuc su doc truc tiep
--    (xac dinh bang cach quet cac *Repository trong
--     backend/src/ConcertTicketing.Infrastructure/Repositories):
--      UserRepository    -> UserAccount, UserRoleAssignment, Role, RefreshToken
--      ConcertRepository -> Concert, Artist, Venue, EventSeat, Seat, Zone, TicketCategory
--      BookingRepository -> Booking, Concert, BookingEventSeatAllocation, Seat, Zone,
--                           TicketCategory, EventSeat, BookingPromotionApplication,
--                           DiscountCode, Promotion
--      HoldReleaseWorker -> Concert
--    KHONG cap SELECT toan schema: bang nao khong nam trong list tren,
--    api_service chi doc duoc qua SP/View nho ownership chaining.
--    (Truoc day dung GRANT SELECT ON SCHEMA::dbo; doi thanh explicit list
--     de:  (a) chi mo dung luong quyen can thiet (least privilege),
--          (b) khong tu dong mo quyen cho BANG MOI them vao dbo sau nay,
--          (c) tranh phai DENY tung bang nhanh cam moi. Luu y: GRANT SCHEMA
--              KHONG bypass duoc DENY object-level, nhung mo qua rong.)
GRANT SELECT ON dbo.UserAccount                TO api_service;  -- Auth: Username/Email/PasswordHash
GRANT SELECT ON dbo.UserRoleAssignment         TO api_service;  -- Auth: Roles
GRANT SELECT ON dbo.Role                       TO api_service;  -- Auth: JOIN Roles
GRANT SELECT ON dbo.RefreshToken               TO api_service;  -- Auth: validate refresh token
GRANT SELECT ON dbo.Concert                    TO api_service;  -- /concerts
GRANT SELECT ON dbo.Artist                     TO api_service;  -- JOIN
GRANT SELECT ON dbo.Venue                      TO api_service;  -- JOIN
GRANT SELECT ON dbo.EventSeat                  TO api_service;  -- /seats
GRANT SELECT ON dbo.Seat                       TO api_service;  -- JOIN
GRANT SELECT ON dbo.Zone                       TO api_service;  -- JOIN
GRANT SELECT ON dbo.TicketCategory             TO api_service;  -- JOIN
GRANT SELECT ON dbo.Booking                    TO api_service;  -- Booking detail
GRANT SELECT ON dbo.BookingEventSeatAllocation TO api_service;  -- Booking detail
GRANT SELECT ON dbo.BookingPromotionApplication TO api_service; -- Booking detail
GRANT SELECT ON dbo.DiscountCode               TO api_service;  -- ApplyPromotion lookup
GRANT SELECT ON dbo.Promotion                  TO api_service;  -- ApplyPromotion JOIN
GRANT SELECT ON dbo.Waitlist                   TO api_service;  -- Waitlist: GetMyEntry JOIN
GRANT SELECT ON dbo.WaitlistEntry              TO api_service;  -- Waitlist: Join/GetMyEntry đọc trực tiếp
GRANT SELECT ON dbo.Queue                      TO api_service;  -- Queue: GetMyEntry JOIN
GRANT SELECT ON dbo.QueueEntry                 TO api_service;  -- Queue: Join/GetMyEntry đọc trực tiếp
GRANT SELECT ON dbo.Payment                    TO api_service;  -- Payment: HMAC verify (đọc Amount/PaymentStatus)
GRANT SELECT ON dbo.Ticket                     TO api_service;
GRANT SELECT ON dbo.Refund                     TO api_service;
GRANT SELECT ON dbo.CheckIn                    TO api_service;
GRANT SELECT ON dbo.WaitlistEntryEventSeatAllocation TO api_service;

-- Quyen doc cac View bao cao. Moi view duoi day tu loc pham vi bang
-- SESSION_CONTEXT(N'UserID') nen cap cho api_service khong lam mat gioi han du lieu:
-- phien khong du dieu kien chi nhan 0 dong (fail-closed).
GRANT SELECT ON dbo.VW_ConcertSalesSummary     TO api_service;
GRANT SELECT ON dbo.VW_CheckInReport           TO api_service;
GRANT SELECT ON dbo.VW_CustomerBookingHistory  TO api_service;
GRANT SELECT ON dbo.VW_WaitlistQueue           TO api_service;
GRANT SELECT ON dbo.VW_ConcertAttendeeList     TO api_service;

-- VW_AuditTrail (FR59/FR59a): truoc day bi REVOKE voi ly do "grant view se vuot DENY
-- tren bang AuditRecord qua ownership chaining". Ly do do DUNG - da do thuc nghiem -
-- nhung he qua cua no la FR59a khong the thuc hien duoc, vi backend chi ket noi bang
-- mot principal duy nhat (api_service) va khong co cach nao "ket noi voi tu cach Admin".
--
-- Cach khep lai dung nhu §23.9 da lam cho bon view bao cao: dua pham vi vao BEN TRONG
-- view thay vi dat o cap principal. VW_AuditTrail nay chi tra du lieu khi nguoi dang
-- dang nhap (SESSION_CONTEXT) giu Role Admin dang hoat dong; moi phien khac nhan 0 dong.
-- DENY SELECT tren bang AuditRecord VAN GIU NGUYEN - doc thang bang van bi chan.
GRANT SELECT ON dbo.VW_AuditTrail TO api_service;

-- 3. Quyen Ghi Ngoại lệ (Operational Data)
-- CHỈ cho phép C# thao tác trực tiếp trên bảng RefreshToken
GRANT INSERT, UPDATE ON dbo.RefreshToken TO api_service;
GRANT SELECT, INSERT, UPDATE, DELETE ON SCHEMA::[HangFire] TO api_service;

-- 4. VÙNG CẤM THUYỆT ĐỐI (Core Business Tables)
-- Chan moi thao tac ghi truc tiep tu C#, bat buoc dung SP
DENY INSERT, UPDATE, DELETE ON dbo.UserAccount                 TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.UserRoleAssignment          TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Booking                     TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.BookingEventSeatAllocation  TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.BookingPromotionApplication TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.EventSeat                   TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Payment                     TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Ticket                      TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.Refund                      TO api_service;
DENY INSERT, UPDATE, DELETE ON dbo.WaitlistEntryEventSeatAllocation TO api_service;

-- Cam doc AuditRecord (chi Admin duoc quyen)
DENY SELECT ON dbo.AuditRecord TO api_service;

GO
