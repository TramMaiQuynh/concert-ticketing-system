CREATE TABLE WaitlistEntry (
    WaitlistEntryID INT IDENTITY(1,1) NOT NULL,
    WaitlistID INT NOT NULL,
    CustomerUserID INT NOT NULL,
    JoinedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    QueuePosition INT,
    EntryStatus VARCHAR(32) NOT NULL,
    OpportunityGrantedTimestamp DATETIME2(7),
    OpportunityExpiryTimestamp DATETIME2(7),
    ResultingBookingID INT,
    CONSTRAINT PK_WaitlistEntry PRIMARY KEY CLUSTERED (WaitlistEntryID),
    CONSTRAINT FK_WaitlistEntry_Waitlist FOREIGN KEY (WaitlistID) REFERENCES Waitlist(WaitlistID),
    CONSTRAINT FK_WaitlistEntry_Customer FOREIGN KEY (CustomerUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_WaitlistEntry_Booking FOREIGN KEY (ResultingBookingID) REFERENCES Booking(BookingID),
    CONSTRAINT CHK_WaitlistEntry_Status CHECK (EntryStatus IN ('Active', 'Granted', 'Expired', 'Fulfilled'))
);

CREATE UNIQUE NONCLUSTERED INDEX UIX_WaitlistEntry_ActivePerCustomer 
ON WaitlistEntry (WaitlistID, CustomerUserID)
WHERE EntryStatus = 'Active';
