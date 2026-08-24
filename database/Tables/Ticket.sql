CREATE TABLE Ticket (
    TicketID INT IDENTITY(1,1) NOT NULL,
    BookingID INT NOT NULL,
    EventSeatID INT NOT NULL,
    ConcertID INT NOT NULL,
    TicketCode VARCHAR(64) NOT NULL,
    TicketStatus VARCHAR(32) NOT NULL,
    IssuedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    UsedTimestamp DATETIME2(7),
    CancelledTimestamp DATETIME2(7),
    CONSTRAINT PK_Ticket PRIMARY KEY CLUSTERED (TicketID),
    CONSTRAINT UQ_Ticket_TicketCode UNIQUE (TicketCode),
    CONSTRAINT FK_Ticket_Booking FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_Ticket_EventSeat FOREIGN KEY (EventSeatID) REFERENCES EventSeat(EventSeatID),
    CONSTRAINT FK_Ticket_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT FK_Ticket_Allocation FOREIGN KEY (BookingID, EventSeatID) REFERENCES BookingEventSeatAllocation(BookingID, EventSeatID),
    CONSTRAINT CHK_Ticket_Status CHECK (TicketStatus IN ('Issued', 'Used', 'Cancelled')),
    CONSTRAINT CHK_Ticket_Timestamps CHECK (
        (CASE WHEN UsedTimestamp IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN CancelledTimestamp IS NOT NULL THEN 1 ELSE 0 END) <= 1
    )
);
