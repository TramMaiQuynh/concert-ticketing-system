CREATE TABLE WaitlistEntry (
    WaitlistEntryID INT IDENTITY(1,1) NOT NULL,
    WaitlistID INT NOT NULL,
    TicketCategoryID INT NOT NULL,
    CustomerUserID INT NOT NULL,
    RequestedQuantity INT NOT NULL,
    JoinedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    QueuePosition INT,
    EntryStatus VARCHAR(32) NOT NULL,
    OpportunityGrantedTimestamp DATETIME2(7),
    OpportunityExpiryTimestamp DATETIME2(7),
    ResultingBookingID INT,
    IsDeleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_WaitlistEntry PRIMARY KEY CLUSTERED (WaitlistEntryID),
    CONSTRAINT FK_WaitlistEntry_Waitlist FOREIGN KEY (WaitlistID) REFERENCES Waitlist(WaitlistID),
    CONSTRAINT FK_WaitlistEntry_TicketCategory FOREIGN KEY (TicketCategoryID) REFERENCES TicketCategory(TicketCategoryID),
    CONSTRAINT FK_WaitlistEntry_Customer FOREIGN KEY (CustomerUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_WaitlistEntry_Booking FOREIGN KEY (ResultingBookingID) REFERENCES Booking(BookingID),
    -- §18.4.1: bao gồm Cancelled (SIP4/BR44a)
    CONSTRAINT CHK_WaitlistEntry_Status CHECK (EntryStatus IN ('Active', 'Granted', 'Expired', 'Fulfilled', 'Cancelled')),
    -- §23.3: RequestedQuantity >= 1 (BR40b)
    CONSTRAINT CHK_WaitlistEntry_RequestedQuantity CHECK (RequestedQuantity >= 1)
);

-- §23.2: UIX_WaitlistEntry_ActivePerCustomer (B1)
CREATE UNIQUE NONCLUSTERED INDEX UIX_WaitlistEntry_ActivePerCustomer 
ON WaitlistEntry (WaitlistID, CustomerUserID)
WHERE EntryStatus = 'Active';
