-- ============================================================
-- Teardown-MockData.sql
-- Dua database PHAT TRIEN ve dung trang thai sau khi deploy:
-- chi con 4 Role, tai khoan 'system' va cac tai khoan THAT (vd. admin bootstrap).
--
-- CANH BAO: CHI dung cho database phat trien / CI. File nay xoa TOAN BO du lieu
-- nghiep vu (venue, zone, seat, concert, template, map, booking, ve, khuyen mai,
-- hang doi, waitlist, audit). KHONG BAO GIO chay tren production.
--
-- VI SAO CAN:
--   Bo test tao ra hang chuc fixture rai rac trong ~15 file: 'Test Concert Live
--   2025', 'Test Stadium', 'Guard Venue C', 'REG Theatre', 'DUMMY'... Vi vay don
--   theo TUNG TEN la vo phuong — danh sach do se moc nat ngay khi co file test moi,
--   va khi do file nay se bao "thanh cong" trong khi van con rac. Cach duy nhat
--   ben vung: xoa het du lieu nghiep vu, giu lai danh tinh that.
--
-- QUY UOC DAT TEN BAT BUOC CHO FIXTURE:
--   Tai khoan do test tao ra PHAI bat dau bang 'test_' hoac 'tmp_'.
--   Hien tai dung 8 ten: test_admin, test_org, test_cust1, test_cust2, test_staff,
--   tmp_admin2, tmp_admin3, tmp_admin4.
--   Nho quy uoc nay ma file phan biet duoc tai khoan test voi tai khoan that
--   (vd. 'admin' do scripts/bootstrap-admin.ps1 tao) ma khong can liet ke cung.
--   Neu them fixture voi tien to khac, phai cap nhat menh de WHERE o cuoi file.
--
-- Chay bang:
--   cd database\Tests
--   sqlcmd -S .\SQLEXPRESS -E -d ConcertTicketingDB -i Teardown-MockData.sql -I
-- (-I la BAT BUOC voi moi lenh tren database nay: 8 bang co filtered index va
--  SQL Server tu choi DELETE ad-hoc khi QUOTED_IDENTIFIER = OFF, loi 1934.)
-- ============================================================

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

-- TRG_AuditLog giu bat bien cho AuditRecord (chan UPDATE/DELETE). Phai tat tam
-- thoi de don duoc vet audit do chinh bo test sinh ra, roi bat lai ngay sau do.
DISABLE TRIGGER TRG_AuditLog ON AuditRecord;
GO

-- Cac fixture account duoc xac dinh MOT LAN, dung lai o cuoi file.
SELECT UserID
INTO #FixtureUser
FROM UserAccount
WHERE Username LIKE 'test[_]%' OR Username LIKE 'tmp[_]%';
GO

-- ------------------------------------------------------------
-- THU TU XOA: con truoc cha.
-- Bám sat khoi xoa o dau 01_SetupMockData.sql (da duoc chung minh qua nhieu lan
-- chay), nhung SUA MOT CHO CO Y: WaitlistEntry va WaitlistEntryEventSeatAllocation
-- duoc xoa TRUOC Booking. Ly do: FK_WaitlistEntry_Booking (ResultingBookingID ->
-- Booking) KHONG co ON DELETE SET NULL, nen xoa Booking truoc se vo loi 547 ngay
-- khi co mot WaitlistEntry da duoc cap co hoi va da sinh booking. Thu tu cu chi
-- dung duoc vi trong thuc te cot do luon NULL — dua vao may man thi khong an toan
-- cho mot lan don sach.
-- ------------------------------------------------------------

DELETE FROM RefreshToken;
DELETE FROM CheckIn;

-- AuditRecord tham chieu UserAccount(ActorUserID), nen phai xoa truoc tai khoan.
DELETE FROM AuditRecord;

DELETE FROM BookingPromotionApplication;
DELETE FROM Ticket;
DELETE FROM Refund;

-- (xem ghi chu o tren: hai bang nay phai dung truoc Booking)
DELETE FROM WaitlistEntryEventSeatAllocation;
DELETE FROM WaitlistEntry;

DELETE FROM BookingEventSeatAllocation;
DELETE FROM Payment;
DELETE FROM Booking;

-- ── Lop StagePass + phan bo Waitlist (con cua EventSeat/Seat/Zone/Venue) ──
DELETE FROM ConcertMapRevisionSeat;
DELETE FROM ConcertMapRevisionObject;
DELETE FROM ConcertMapRevisionSection;
DELETE FROM ConcertMapRevisionFloor;
DELETE FROM ConcertMapRevision;
DELETE FROM ConcertMap;
DELETE FROM TemplateSeat;
DELETE FROM TemplateObject;
DELETE FROM TemplateSection;
DELETE FROM TemplateFloor;
DELETE FROM VenueTemplateVersion;
DELETE FROM VenueTemplate;

DELETE FROM DiscountCode;
DELETE FROM Promotion;
DELETE FROM QueueEntry;
DELETE FROM Queue;
DELETE FROM Waitlist;

DELETE FROM EventSeat;
DELETE FROM TicketCategory;
DELETE FROM CheckinStaffAssignment;

-- ConcertArtist tham chieu CA Concert LAN Artist, nen phai xoa truoc ca hai.
DELETE FROM ConcertArtist;
DELETE FROM Concert;

DELETE FROM Artist;
DELETE FROM Seat;
DELETE FROM Zone;
DELETE FROM Venue;

-- ------------------------------------------------------------
-- Tai khoan: CHI xoa fixture, giu lai tai khoan that.
-- UserRoleAssignment la con cua UserAccount -> phai xoa truoc.
-- ------------------------------------------------------------
DELETE FROM UserRoleAssignment WHERE UserID IN (SELECT UserID FROM #FixtureUser);
DELETE FROM UserAccount        WHERE UserID IN (SELECT UserID FROM #FixtureUser);

DROP TABLE #FixtureUser;

ENABLE TRIGGER TRG_AuditLog ON AuditRecord;
GO

-- ------------------------------------------------------------
-- TU KIEM: sau khi don, chi duoc con tai khoan that + 'system'.
-- In ra de nguoi chay thay ngay trang thai cuoi, khong phai doan.
-- ------------------------------------------------------------
PRINT '------------------------------------------------';
PRINT 'TEARDOWN XONG — trang thai cuoi:';
SELECT 'Role'        AS Muc, COUNT(*) AS SoLuong FROM Role
UNION ALL SELECT 'UserAccount',       COUNT(*) FROM UserAccount
UNION ALL SELECT 'UserRoleAssignment',COUNT(*) FROM UserRoleAssignment
UNION ALL SELECT 'Venue',             COUNT(*) FROM Venue
UNION ALL SELECT 'Concert',           COUNT(*) FROM Concert
UNION ALL SELECT 'EventSeat',         COUNT(*) FROM EventSeat
UNION ALL SELECT 'Booking',           COUNT(*) FROM Booking
UNION ALL SELECT 'AuditRecord',       COUNT(*) FROM AuditRecord;
PRINT '------------------------------------------------';
GO
