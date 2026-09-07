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
    CONSTRAINT CHK_Allocation_Status CHECK (AllocationStatus IN ('Active', 'Released')),
    -- AI03 (dac ta muc 23.3): PriceSnapshot nam trong danh sach cot tien phai co
    -- CHECK (Amount >= 0), ngang hang voi BasePrice/SalePrice/Amount. Truoc day
    -- cot nay la cot tien DUY NHAT khong co CHECK — mot gia am loi vao day se
    -- chay thang vao fn_CalculateBookingSubtotal va lam Subtotal nho hon that.
    CONSTRAINT CHK_Allocation_PriceSnapshot CHECK (PriceSnapshot >= 0)
);

CREATE UNIQUE NONCLUSTERED INDEX UIX_Allocation_ActiveEventSeat 
ON BookingEventSeatAllocation (EventSeatID)
WHERE AllocationStatus = 'Active';
