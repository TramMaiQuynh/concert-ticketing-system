CREATE TABLE EventSeat (
    EventSeatID INT IDENTITY(1,1) NOT NULL,
    ConcertID INT NOT NULL,
    SeatID INT NOT NULL,
    TicketCategoryID INT NOT NULL,
    SalePrice DECIMAL(18,0) NOT NULL,
    InventoryStatus VARCHAR(32) NOT NULL,
    AddedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    UnavailabilityReason NVARCHAR(500),
    IsDeleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_EventSeat PRIMARY KEY CLUSTERED (EventSeatID),
    CONSTRAINT UQ_EventSeat_Concert_Seat UNIQUE (ConcertID, SeatID),
    CONSTRAINT FK_EventSeat_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT FK_EventSeat_Seat FOREIGN KEY (SeatID) REFERENCES Seat(SeatID),
    CONSTRAINT FK_EventSeat_TicketCategory FOREIGN KEY (ConcertID, TicketCategoryID) REFERENCES TicketCategory(ConcertID, TicketCategoryID),
    CONSTRAINT CHK_EventSeat_SalePrice CHECK (SalePrice >= 0),
    CONSTRAINT CHK_EventSeat_InventoryStatus CHECK (InventoryStatus IN ('Available', 'OnHold', 'OnHoldForWaitlist', 'Booked', 'Unavailable'))
);
