USE ConcertTicketingDB;
GO

SET NOCOUNT ON;

PRINT 'Seeding 20 Famous Concerts...';

-- 1. ARTISTS
CREATE TABLE #TempArtists (ArtistName NVARCHAR(255), ArtistID INT);
INSERT INTO Artist (ArtistName)
OUTPUT INSERTED.ArtistName, INSERTED.ArtistID INTO #TempArtists
VALUES 
    ('Queen'), ('The Beatles'), ('Michael Jackson'), ('Pink Floyd'), 
    ('Nirvana'), ('Daft Punk'), ('Oasis'), ('Johnny Cash'), 
    ('The Rolling Stones'), ('Simon & Garfunkel'), ('AC/DC'), 
    ('Beyoncé'), ('Elton John'), ('Metallica'), ('U2'), 
    ('David Bowie'), ('Taylor Swift'), ('Led Zeppelin'), 
    ('Adele'), ('Coldplay');

-- 2. VENUES
CREATE TABLE #TempVenues (VenueName NVARCHAR(255), VenueID INT);
INSERT INTO Venue (VenueName, Address, VenueStatus, CreatedTimestamp, UpdatedTimestamp)
OUTPUT INSERTED.VenueName, INSERTED.VenueID INTO #TempVenues
VALUES
    ('Wembley Stadium', 'London, UK', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Shea Stadium', 'New York, NY', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Rose Bowl', 'Pasadena, CA', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Potsdamer Platz', 'Berlin, Germany', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Sony Music Studios', 'New York, NY', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Empire Polo Club (Coachella)', 'Indio, CA', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Knebworth Park', 'Stevenage, UK', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Folsom State Prison', 'Folsom, CA', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Copacabana Beach', 'Rio de Janeiro, Brazil', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Central Park', 'New York, NY', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Estadio Monumental', 'Buenos Aires, Argentina', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Worthy Farm (Glastonbury)', 'Pilton, UK', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Tushino Airfield', 'Moscow, Russia', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Hammersmith Odeon', 'London, UK', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('SoFi Stadium', 'Inglewood, CA', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('O2 Arena', 'London, UK', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Royal Albert Hall', 'London, UK', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Slane Castle', 'County Meath, Ireland', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Tokyo Dome', 'Tokyo, Japan', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME()),
    ('Madison Square Garden', 'New York, NY', 'Active', SYSUTCDATETIME(), SYSUTCDATETIME());

-- Generate Zones and Seats for all Venues
PRINT 'Generating Zones and Seats for Venues...';
DECLARE @vID INT, @zID INT, @vName NVARCHAR(255);
DECLARE cur_venue CURSOR FOR SELECT VenueID, VenueName FROM #TempVenues;
OPEN cur_venue;
FETCH NEXT FROM cur_venue INTO @vID, @vName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Zone 1: VIP (Front)
    INSERT INTO Zone (VenueID, ZoneCode, ZoneName, ZoneDescription) VALUES (@vID, 'VIP', 'VIP Front Row', 'Close to stage');
    SET @zID = SCOPE_IDENTITY();
    
    DECLARE @s INT = 1;
    WHILE @s <= 20
    BEGIN
        INSERT INTO Seat (ZoneID, VenueID, SeatCode, SeatLabel) VALUES (@zID, @vID, CONCAT('V', @s), CONCAT('VIP Seat ', @s));
        SET @s = @s + 1;
    END

    -- Zone 2: GA (General Admission)
    INSERT INTO Zone (VenueID, ZoneCode, ZoneName, ZoneDescription) VALUES (@vID, 'GA', 'General Admission', 'Standing area');
    SET @zID = SCOPE_IDENTITY();
    
    SET @s = 1;
    WHILE @s <= 50
    BEGIN
        INSERT INTO Seat (ZoneID, VenueID, SeatCode, SeatLabel) VALUES (@zID, @vID, CONCAT('G', @s), CONCAT('GA Seat ', @s));
        SET @s = @s + 1;
    END

    FETCH NEXT FROM cur_venue INTO @vID, @vName;
END
CLOSE cur_venue;
DEALLOCATE cur_venue;


-- 3. CONCERTS
PRINT 'Generating Concerts...';
CREATE TABLE #ConcertMap (ArtistName NVARCHAR(100), VenueName NVARCHAR(100), ConcertName NVARCHAR(255), StartDate DATETIME2, EndDate DATETIME2);

INSERT INTO #ConcertMap (ArtistName, VenueName, ConcertName, StartDate, EndDate) VALUES
('Queen', 'Wembley Stadium', 'Live Aid 1985', '2026-10-13 18:00:00', '2026-10-13 22:00:00'),
('The Beatles', 'Shea Stadium', 'At Shea Stadium', '2026-10-15 19:00:00', '2026-10-15 21:00:00'),
('Michael Jackson', 'Rose Bowl', 'Super Bowl XXVII Halftime', '2026-10-31 20:00:00', '2026-10-31 23:00:00'),
('Pink Floyd', 'Potsdamer Platz', 'The Wall Live in Berlin', '2026-11-21 19:30:00', '2026-11-21 23:30:00'),
('Nirvana', 'Sony Music Studios', 'MTV Unplugged in New York', '2026-11-18 20:00:00', '2026-11-18 22:00:00'),
('Daft Punk', 'Empire Polo Club (Coachella)', 'Alive 2007', '2026-11-29 22:00:00', '2026-11-30 01:00:00'),
('Oasis', 'Knebworth Park', 'Oasis at Knebworth', '2026-12-10 18:00:00', '2026-12-10 22:30:00'),
('Johnny Cash', 'Folsom State Prison', 'At Folsom Prison', '2026-12-13 10:00:00', '2026-12-13 12:00:00'),
('The Rolling Stones', 'Copacabana Beach', 'A Bigger Bang Tour', '2027-01-18 20:00:00', '2027-01-18 23:00:00'),
('Simon & Garfunkel', 'Central Park', 'The Concert in Central Park', '2027-01-19 19:00:00', '2027-01-19 22:00:00'),
('AC/DC', 'Estadio Monumental', 'Live at River Plate', '2027-02-04 21:00:00', '2027-02-04 23:30:00'),
('Beyoncé', 'Empire Polo Club (Coachella)', 'Homecoming', '2027-02-14 21:00:00', '2027-02-14 23:59:00'),
('Elton John', 'Worthy Farm (Glastonbury)', 'Farewell Yellow Brick Road', '2027-02-25 19:30:00', '2027-02-25 22:30:00'),
('Metallica', 'Tushino Airfield', 'Monsters of Rock', '2027-03-28 18:00:00', '2027-03-28 23:00:00'),
('U2', 'Slane Castle', 'U2 Go Home', '2027-03-01 19:00:00', '2027-03-01 22:00:00'),
('David Bowie', 'Hammersmith Odeon', 'Ziggy Stardust The Motion Picture', '2027-04-03 20:00:00', '2027-04-03 22:30:00'),
('Taylor Swift', 'SoFi Stadium', 'The Eras Tour', '2027-04-09 19:30:00', '2027-04-09 23:15:00'),
('Led Zeppelin', 'O2 Arena', 'Celebration Day', '2027-05-10 20:00:00', '2027-05-10 23:00:00'),
('Adele', 'Royal Albert Hall', 'Live at the Royal Albert Hall', '2027-05-22 19:30:00', '2027-05-22 21:30:00'),
('Coldplay', 'Tokyo Dome', 'Music of the Spheres', '2027-06-15 18:00:00', '2027-06-15 21:00:00');

-- DR-01 / BR01: Concert.OrganizerUserID phai la User co Role Organizer.
-- Seed tao mot Organizer user thay vi dung literal 1 (system user - khong co Role).
IF NOT EXISTS (SELECT 1 FROM UserAccount WHERE Username = 'seed_organizer')
BEGIN
    INSERT INTO UserAccount (Username, AccountStatus, Email, DisplayName)
    VALUES ('seed_organizer', 'Active', 'seedorg@concert.test', 'Seed Organizer');
    DECLARE @SeedOrgUserID INT = SCOPE_IDENTITY();

    INSERT INTO UserRoleAssignment (UserID, RoleID, AssignmentStatus)
    SELECT @SeedOrgUserID, RoleID, 'Active'
    FROM   Role
    WHERE  RoleName = 'Organizer' AND RoleStatus = 'Active';
END
DECLARE @SeedOrgID INT = (SELECT UserID FROM UserAccount WHERE Username = 'seed_organizer');

DECLARE @cArtistID INT, @cVenueID INT, @cName NVARCHAR(255), @cStart DATETIME2, @cEnd DATETIME2;
DECLARE @insertedConcerts TABLE (ConcertID INT, VenueID INT);
DECLARE cur_concert CURSOR FOR 
    SELECT a.ArtistID, v.VenueID, cm.ConcertName, cm.StartDate, cm.EndDate 
    FROM #ConcertMap cm
    JOIN #TempArtists a ON a.ArtistName = cm.ArtistName
    JOIN #TempVenues v ON v.VenueName = cm.VenueName;
OPEN cur_concert;
FETCH NEXT FROM cur_concert INTO @cArtistID, @cVenueID, @cName, @cStart, @cEnd;

WHILE @@FETCH_STATUS = 0
BEGIN
    DECLARE @cID INT;
    
    INSERT INTO Concert (ArtistID, VenueID, OrganizerUserID, ConcertName, StartDatetime, EndDatetime, ConcertStatus, SaleStartDatetime, SaleEndDatetime, PurchaseLimit, TemporaryHoldDuration, FairAccessEnabled, WaitlistEnabled, SalesPaused, CancellationPolicy, RefundPolicy)
    VALUES (@cArtistID, @cVenueID, @SeedOrgID, @cName, @cStart, @cEnd, 'OnSale', DATEADD(day, -30, @cStart), DATEADD(day, -1, @cStart), 4, 15, 0, 0, 0, 'No cancellation', 'Refund only if event cancelled');
    
    SET @cID = SCOPE_IDENTITY();
    INSERT INTO @insertedConcerts (ConcertID, VenueID) VALUES (@cID, @cVenueID);

    FETCH NEXT FROM cur_concert INTO @cArtistID, @cVenueID, @cName, @cStart, @cEnd;
END
CLOSE cur_concert;
DEALLOCATE cur_concert;

-- 4. TICKET CATEGORIES & EVENT SEATS
PRINT 'Generating Ticket Categories and Event Seats...';

DECLARE @cxID INT, @cvID INT;
DECLARE cur_es CURSOR FOR SELECT ConcertID, VenueID FROM @insertedConcerts;
OPEN cur_es;
FETCH NEXT FROM cur_es INTO @cxID, @cvID;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Add Ticket Categories
    DECLARE @vipCatID INT, @gaCatID INT;
    INSERT INTO TicketCategory (ConcertID, CategoryName, CategoryDescription, CategoryStatus) VALUES (@cxID, 'VIP', 'Front Stage VIP Access', 'Active');
    SET @vipCatID = SCOPE_IDENTITY();
    
    INSERT INTO TicketCategory (ConcertID, CategoryName, CategoryDescription, CategoryStatus) VALUES (@cxID, 'General Admission', 'Standing Area', 'Active');
    SET @gaCatID = SCOPE_IDENTITY();

    -- Map VIP Seats
    INSERT INTO EventSeat (SeatID, ConcertID, TicketCategoryID, SalePrice, InventoryStatus, AddedTimestamp)
    SELECT SeatID, @cxID, @vipCatID, 250.00, 'Available', SYSUTCDATETIME()
    FROM Seat s JOIN Zone z ON s.ZoneID = z.ZoneID
    WHERE z.ZoneCode = 'VIP' AND s.VenueID = @cvID;

    -- Map GA Seats
    INSERT INTO EventSeat (SeatID, ConcertID, TicketCategoryID, SalePrice, InventoryStatus, AddedTimestamp)
    SELECT SeatID, @cxID, @gaCatID, 99.00, 'Available', SYSUTCDATETIME()
    FROM Seat s JOIN Zone z ON s.ZoneID = z.ZoneID
    WHERE z.ZoneCode = 'GA' AND s.VenueID = @cvID;

    FETCH NEXT FROM cur_es INTO @cxID, @cvID;
END
CLOSE cur_es;
DEALLOCATE cur_es;

DROP TABLE #TempArtists;
DROP TABLE #TempVenues;
DROP TABLE #ConcertMap;

PRINT 'Seed Data Completed Successfully.';
