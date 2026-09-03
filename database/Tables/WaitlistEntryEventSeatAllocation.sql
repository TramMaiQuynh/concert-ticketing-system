CREATE TABLE WaitlistEntryEventSeatAllocation (
    WaitlistEntryID INT NOT NULL,
    EventSeatID INT NOT NULL,
    AllocationTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    ReleaseTimestamp DATETIME2(7),
    AllocationStatus VARCHAR(32) NOT NULL,
    CONSTRAINT PK_WaitlistEntryESA PRIMARY KEY CLUSTERED (WaitlistEntryID, EventSeatID),
    CONSTRAINT FK_WaitlistEntryESA_Entry FOREIGN KEY (WaitlistEntryID) REFERENCES WaitlistEntry(WaitlistEntryID),
    CONSTRAINT FK_WaitlistEntryESA_EventSeat FOREIGN KEY (EventSeatID) REFERENCES EventSeat(EventSeatID),
    -- §18.4.1: Active/Released (cùng domain với BookingEventSeatAllocation)
    CONSTRAINT CHK_WaitlistEntryESA_Status CHECK (AllocationStatus IN ('Active', 'Released'))
);
