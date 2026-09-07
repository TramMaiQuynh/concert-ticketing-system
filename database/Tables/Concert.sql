CREATE TABLE Concert (
    ConcertID INT IDENTITY(1,1) NOT NULL,
    OrganizerUserID INT NULL,
    ArtistID INT NULL,
    VenueID INT NULL,
    ConcertName NVARCHAR(255) NOT NULL,
    StartDatetime DATETIME2(7) NULL,
    EndDatetime DATETIME2(7) NULL,
    ConcertStatus VARCHAR(32) NOT NULL,
    SaleStartDatetime DATETIME2(7),
    SaleEndDatetime DATETIME2(7),
    PurchaseLimit INT NOT NULL,
    TemporaryHoldDuration INT,
    FairAccessEnabled BIT NOT NULL,
    WaitlistEnabled BIT NOT NULL,
    SalesPaused BIT NOT NULL,
    CancellationPolicy NVARCHAR(500),
    RefundPolicy NVARCHAR(500),
    CancellationDeadlineHours INT CONSTRAINT DF_Concert_CancelDeadline DEFAULT 48,
    RefundPercentage DECIMAL(5,2) CONSTRAINT DF_Concert_RefundPct DEFAULT 100.00,
    CONSTRAINT PK_Concert PRIMARY KEY CLUSTERED (ConcertID),
    CONSTRAINT FK_Concert_Organizer FOREIGN KEY (OrganizerUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_Concert_Artist FOREIGN KEY (ArtistID) REFERENCES Artist(ArtistID),
    CONSTRAINT FK_Concert_Venue FOREIGN KEY (VenueID) REFERENCES Venue(VenueID),
    CONSTRAINT CHK_Concert_Status CHECK (ConcertStatus IN ('Draft', 'Published', 'OnSale', 'SaleClosed', 'Completed', 'Cancelled')),
    CONSTRAINT CHK_Concert_Dates CHECK (EndDatetime IS NULL OR StartDatetime IS NULL OR EndDatetime > StartDatetime),
    CONSTRAINT CHK_Concert_SaleDates CHECK (SaleEndDatetime >= SaleStartDatetime),
    -- Phong thu: PurchaseLimit phai > 0 (BR20); TemporaryHoldDuration neu co phai > 0
    CONSTRAINT CHK_Concert_PurchaseLimit CHECK (PurchaseLimit > 0),
    CONSTRAINT CHK_Concert_HoldDuration CHECK (TemporaryHoldDuration IS NULL OR TemporaryHoldDuration > 0),
    -- Ty le hoan tien la phan tram: mien [0..100]. DECIMAL(5,2) tu no cho phep
    -- toi 999.99 va ca gia tri am - phai chan tai DB, khong de logic SP la lop
    -- bao ve duy nhat (SP co the bi thay the/bo sot; du lieu thi o lai mai mai).
    CONSTRAINT CHK_Concert_RefundPercentage CHECK (RefundPercentage IS NULL OR (RefundPercentage >= 0 AND RefundPercentage <= 100)),
    -- Han huy tinh nguoc tu StartDatetime nen khong the am (0 = huy den sat gio dien).
    CONSTRAINT CHK_Concert_CancelDeadline CHECK (CancellationDeadlineHours IS NULL OR CancellationDeadlineHours >= 0)
);
