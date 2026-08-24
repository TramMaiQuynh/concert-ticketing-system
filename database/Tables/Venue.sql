CREATE TABLE Venue (
    VenueID INT IDENTITY(1,1) NOT NULL,
    VenueName NVARCHAR(255) NOT NULL,
    Address NVARCHAR(500),
    VenueStatus VARCHAR(32) NOT NULL,
    CreatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_Venue PRIMARY KEY CLUSTERED (VenueID),
    -- Domain per §18.4.1: Active (đang hoạt động), Inactive (tạm ngưng)
    CONSTRAINT CHK_Venue_Status CHECK (VenueStatus IN ('Active', 'Inactive'))
);
