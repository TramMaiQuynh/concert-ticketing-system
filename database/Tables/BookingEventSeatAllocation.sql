CREATE TABLE BookingEventSeatAllocation (
    BookingID INT NOT NULL,
    EventSeatID INT NOT NULL,
    AllocationTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    ReleaseTimestamp DATETIME2(7),
    AllocationStatus VARCHAR(32) NOT NULL,
    PriceSnapshot DECIMAL(18,0) NOT NULL,
    CONSTRAINT PK_BookingEventSeatAllocation PRIMARY KEY CLUSTERED (BookingID, EventSeatID),
    CONSTRAINT FK_BookingAllocation_Booking FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BookingAllocation_EventSeat FOREIGN KEY (EventSeatID) REFERENCES EventSeat(EventSeatID),
    CONSTRAINT CHK_Allocation_Status CHECK (AllocationStatus IN ('Active', 'Released'))
);

CREATE UNIQUE NONCLUSTERED INDEX UIX_Allocation_ActiveEventSeat 
ON BookingEventSeatAllocation (EventSeatID)
WHERE AllocationStatus = 'Active';
