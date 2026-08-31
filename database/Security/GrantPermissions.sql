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
GRANT SELECT ON dbo.Booking              TO app_organizer;
GRANT SELECT ON dbo.Payment              TO app_organizer;
GRANT SELECT ON dbo.Ticket               TO app_organizer;
GRANT SELECT ON dbo.Promotion            TO app_organizer;
GRANT SELECT ON dbo.DiscountCode         TO app_organizer;
GRANT SELECT ON dbo.CheckIn              TO app_organizer;
GRANT SELECT ON dbo.Waitlist             TO app_organizer;
GRANT SELECT ON dbo.WaitlistEntry        TO app_organizer;

-- Quyen xem Views bao cao
GRANT SELECT ON dbo.VW_ConcertSalesSummary   TO app_organizer;
GRANT SELECT ON dbo.VW_ActiveInventoryStatus TO app_organizer;
GRANT SELECT ON dbo.VW_CheckInReport         TO app_organizer;
GRANT SELECT ON dbo.VW_WaitlistQueue         TO app_organizer;

-- Quyen thuc thi Stored Procedures lien quan
GRANT EXECUTE ON dbo.sp_ProcessRefund   TO app_organizer;
GRANT EXECUTE ON dbo.sp_ApplyPromotion  TO app_organizer;

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
GRANT SELECT ON dbo.Promotion        TO app_customer;
GRANT SELECT ON dbo.DiscountCode     TO app_customer;

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
GRANT SELECT ON dbo.VW_CheckInReport        TO app_checkinstaff;

-- Quyen thuc thi SP check-in
GRANT EXECUTE ON dbo.sp_CheckInTicket TO app_checkinstaff;

-- Chan moi quyen ghi truc tiep khac
DENY INSERT, UPDATE, DELETE ON dbo.Ticket       TO app_checkinstaff;
DENY INSERT, UPDATE, DELETE ON dbo.Booking      TO app_checkinstaff;
DENY SELECT  ON dbo.AuditRecord                 TO app_checkinstaff;
DENY SELECT  ON dbo.Payment                     TO app_checkinstaff;
DENY SELECT  ON dbo.UserAccount                 TO app_checkinstaff;

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

-- Quyen doc cac View bao cao (neu sau nay backend doc truc tiep).
-- KHONG grant VW_AuditTrail: view nay doc AuditRecord (chi Admin duoc doc,
-- theo FR59). Grant VIEW se cho phep doc qua ownership chaining, vo hieu hoa
-- DENY tren bang AuditRecord -> do do phai loai tru va REVOKE neu dang co.
GRANT SELECT ON dbo.VW_ConcertSalesSummary     TO api_service;
GRANT SELECT ON dbo.VW_CheckInReport           TO api_service;
GRANT SELECT ON dbo.VW_CustomerBookingHistory  TO api_service;
GRANT SELECT ON dbo.VW_WaitlistQueue           TO api_service;
REVOKE SELECT ON dbo.VW_AuditTrail FROM api_service;

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

-- Cam doc AuditRecord (chi Admin duoc quyen)
DENY SELECT ON dbo.AuditRecord TO api_service;

GO
