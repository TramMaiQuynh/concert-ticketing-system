CREATE TABLE Waitlist (
    WaitlistID INT IDENTITY(1,1) NOT NULL,
    ConcertID INT NOT NULL,
    WaitlistStatus VARCHAR(32) NOT NULL,
    OpenTimestamp DATETIME2(7),
    CloseTimestamp DATETIME2(7),
    AllocationPolicy VARCHAR(32) NOT NULL,
    IsDeleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Waitlist PRIMARY KEY CLUSTERED (WaitlistID),
    CONSTRAINT UQ_Waitlist_Concert UNIQUE (ConcertID),
    CONSTRAINT FK_Waitlist_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT CHK_Waitlist_Status CHECK (WaitlistStatus IN ('Open', 'Closed')),
    CONSTRAINT CHK_Waitlist_Policy CHECK (AllocationPolicy IN ('FIFO', 'RANDOM'))
);
