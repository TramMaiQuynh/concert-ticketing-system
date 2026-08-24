CREATE TABLE CheckIn (
    CheckInID INT IDENTITY(1,1) NOT NULL,
    TicketID INT NOT NULL,
    ConcertID INT NOT NULL,
    CheckInStaffUserID INT NOT NULL,
    CheckInTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    ValidationResult VARCHAR(32) NOT NULL,
    ValidationInformation NVARCHAR(500),
    CONSTRAINT PK_CheckIn PRIMARY KEY CLUSTERED (CheckInID),
    CONSTRAINT UQ_CheckIn_Ticket UNIQUE (TicketID),
    CONSTRAINT FK_CheckIn_Ticket FOREIGN KEY (TicketID) REFERENCES Ticket(TicketID),
    CONSTRAINT FK_CheckIn_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT FK_CheckIn_Staff FOREIGN KEY (CheckInStaffUserID) REFERENCES UserAccount(UserID)
);
