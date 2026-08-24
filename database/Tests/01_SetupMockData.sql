-- ============================================================
-- 01_SetupMockData.sql
-- Xoa het data cu, seeding du lieu test sach.
-- Schema khop voi deploy.ps1 thuc te.
-- ============================================================
USE ConcertTicketingDB;
GO

SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET NOCOUNT ON;
GO

-- Disable AuditLog trigger de cho phep xoa AuditRecord (bat bien khi UPDATE/DELETE)
DISABLE TRIGGER TRG_AuditLog ON AuditRecord;

-- Xoa theo thu tu FK (child truoc parent)
DELETE FROM CheckIn;
DELETE FROM AuditRecord;
DELETE FROM BookingPromotionApplication;
DELETE FROM Ticket;
DELETE FROM Refund;
DELETE FROM Payment;
DELETE FROM BookingEventSeatAllocation;
DELETE FROM Booking;
DELETE FROM DiscountCode;
DELETE FROM Promotion;
DELETE FROM QueueEntry;
DELETE FROM Queue;
DELETE FROM WaitlistEntry;
DELETE FROM Waitlist;
DELETE FROM EventSeat;
DELETE FROM TicketCategory;
DELETE FROM CheckinStaffAssignment;
DELETE FROM Concert;
DELETE FROM Artist;
DELETE FROM Seat;
DELETE FROM Zone;
DELETE FROM Venue;
DELETE FROM UserRoleAssignment;
DELETE FROM UserAccount WHERE Username NOT IN ('system');

ENABLE TRIGGER TRG_AuditLog ON AuditRecord;

-- ============================================================
-- SEED USERS (5 user test)
-- ============================================================
INSERT INTO UserAccount (Username, AccountStatus, Email, DisplayName)
VALUES 
('test_admin',  'Active', 'admin@test.com',  'Admin Test'),
('test_org',    'Active', 'org@test.com',    'Organizer Test'),
('test_cust1',  'Active', 'cust1@test.com',  'Customer 1'),
('test_cust2',  'Active', 'cust2@test.com',  'Customer 2'),
('test_staff',  'Active', 'staff@test.com',  'Staff Test');

-- Phan quyen: Role 1=Admin, 2=Organizer, 3=Customer, 4=Staff
INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
SELECT UserID, 1, 'Active' FROM UserAccount WHERE Username = 'test_admin';
INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
SELECT UserID, 2, 'Active' FROM UserAccount WHERE Username = 'test_org';
INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
SELECT UserID, 3, 'Active' FROM UserAccount WHERE Username = 'test_cust1';
INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
SELECT UserID, 3, 'Active' FROM UserAccount WHERE Username = 'test_cust2';
INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
SELECT UserID, 4, 'Active' FROM UserAccount WHERE Username = 'test_staff';

-- ============================================================
-- SEED VENUE, ZONE, SEAT
-- ============================================================
INSERT INTO Venue (VenueName, Address, VenueStatus)
VALUES ('Test Stadium', '123 Test Street, HCM', 'Active');
DECLARE @VenueID INT = SCOPE_IDENTITY();

INSERT INTO Zone (VenueID, ZoneCode, ZoneName)
VALUES (@VenueID, 'VIP', 'VIP Zone'), (@VenueID, 'GA', 'General Admission');
DECLARE @ZoneVIP INT = (SELECT ZoneID FROM Zone WHERE ZoneCode = 'VIP' AND VenueID = @VenueID);

-- 6 ghe VIP (dung 5 cho test chinh + 1 du phong)
INSERT INTO Seat (ZoneID, VenueID, SeatCode, SeatLabel)
VALUES
(@ZoneVIP, @VenueID, 'V1', 'VIP Row A Seat 1'),
(@ZoneVIP, @VenueID, 'V2', 'VIP Row A Seat 2'),
(@ZoneVIP, @VenueID, 'V3', 'VIP Row A Seat 3'),
(@ZoneVIP, @VenueID, 'V4', 'VIP Row A Seat 4'),
(@ZoneVIP, @VenueID, 'V5', 'VIP Row A Seat 5'),
(@ZoneVIP, @VenueID, 'V6', 'VIP Row A Seat 6');

-- ============================================================
-- SEED ARTIST, CONCERT
-- ============================================================
INSERT INTO Artist (ArtistName, ArtistDescription)
VALUES ('Test Artist', 'A test artist for automated testing.');
DECLARE @ArtistID INT = SCOPE_IDENTITY();

DECLARE @OrgID INT = (SELECT UserID FROM UserAccount WHERE Username = 'test_org');
DECLARE @CustID1 INT = (SELECT UserID FROM UserAccount WHERE Username = 'test_cust1');
DECLARE @CustID2 INT = (SELECT UserID FROM UserAccount WHERE Username = 'test_cust2');
DECLARE @StaffID INT = (SELECT UserID FROM UserAccount WHERE Username = 'test_staff');

INSERT INTO Concert (
    OrganizerUserID, ArtistID, VenueID, ConcertName,
    ConcertStatus, StartDatetime, EndDatetime,
    PurchaseLimit, TemporaryHoldDuration,
    FairAccessEnabled, WaitlistEnabled, SalesPaused
)
VALUES (
    @OrgID, @ArtistID, @VenueID, 'Test Concert Live 2025',
    'OnSale',
    DATEADD(DAY, 30, SYSDATETIME()), DATEADD(DAY, 30, DATEADD(HOUR, 3, SYSDATETIME())),
    4, 900,   -- PurchaseLimit=4, HoldDuration=15min
    0, 1, 0
);
DECLARE @ConcertID INT = SCOPE_IDENTITY();

-- Staff assignment
INSERT INTO CheckinStaffAssignment (ConcertID, UserID)
VALUES (@ConcertID, @StaffID);

-- TicketCategory
INSERT INTO TicketCategory (ConcertID, CategoryName, CategoryStatus)
VALUES (@ConcertID, 'VIP Gold', 'Active');
DECLARE @CatID INT = SCOPE_IDENTITY();

-- EventSeat (6 ghe, gia 1,000,000 VND)
INSERT INTO EventSeat (ConcertID, SeatID, TicketCategoryID, InventoryStatus, SalePrice)
SELECT @ConcertID, SeatID, @CatID, 'Available', 1000000
FROM Seat WHERE ZoneID = @ZoneVIP;

-- ============================================================
-- SEED PROMOTION + DISCOUNT CODE
-- ============================================================
INSERT INTO Promotion (
    ConcertID, PromotionName, DiscountType, DiscountValue,
    StartDatetime, EndDatetime, UsageLimit, CodeRequiredFlag, PromotionStatus
)
VALUES (
    @ConcertID, 'SUMMER_SALE_200K', 'FIXED', 200000,
    SYSDATETIME(), DATEADD(DAY, 30, SYSDATETIME()),
    100, 1, 'Active'
);
DECLARE @PromoID INT = SCOPE_IDENTITY();

INSERT INTO DiscountCode (PromotionID, CodeValue, ValidFromDatetime, ValidToDatetime, CodeStatus)
VALUES (@PromoID, 'SUMMER200K', SYSDATETIME(), DATEADD(DAY, 30, SYSDATETIME()), 'Active');
DECLARE @CodeID INT = SCOPE_IDENTITY();

-- ============================================================
-- SEED WAITLIST + QUEUE
-- ============================================================
INSERT INTO Waitlist (ConcertID, WaitlistStatus, AllocationPolicy)
VALUES (@ConcertID, 'Open', 'FIFO');

INSERT INTO Queue (ConcertID, QueueStatus, AdmissionCapacity, FairAccessPolicy)
VALUES (@ConcertID, 'Open', 1000, 'RANDOM');

PRINT '== Mock Data Setup Complete ==';
PRINT 'ConcertID   = ' + CAST(@ConcertID AS VARCHAR);
PRINT 'PromotionID = ' + CAST(@PromoID AS VARCHAR);
PRINT 'DiscountCodeID = ' + CAST(@CodeID AS VARCHAR);
PRINT 'OrganizerID = ' + CAST(@OrgID AS VARCHAR);
PRINT 'CustomerID1 = ' + CAST(@CustID1 AS VARCHAR);
PRINT 'StaffID     = ' + CAST(@StaffID AS VARCHAR);
GO



