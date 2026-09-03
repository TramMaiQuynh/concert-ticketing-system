CREATE TABLE Booking (
    BookingID INT IDENTITY(1,1) NOT NULL,
    CustomerUserID INT NOT NULL,
    ConcertID INT NOT NULL,
    BookingStatus VARCHAR(32) NOT NULL,
    HoldStartDatetime DATETIME2(7),
    HoldExpiryDatetime DATETIME2(7),
    SubtotalAmount DECIMAL(18,0) NOT NULL,
    FinalAmount DECIMAL(18,0) NOT NULL,
    CreatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    ConfirmedTimestamp DATETIME2(7),
    CancelledTimestamp DATETIME2(7),
    ExpiredTimestamp DATETIME2(7),
    IsDeleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Booking PRIMARY KEY CLUSTERED (BookingID),
    CONSTRAINT FK_Booking_Customer FOREIGN KEY (CustomerUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_Booking_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT CHK_Booking_Status CHECK (BookingStatus IN ('Pending', 'Confirmed', 'Expired', 'Cancelled')),
    CONSTRAINT CHK_Booking_HoldDates CHECK (HoldExpiryDatetime > HoldStartDatetime),
    -- BR16 (§12.9.1): Booking Pending = Temporary Hold dang hieu luc
    -- -> bat buoc co HoldStartDatetime va HoldExpiryDatetime.
    -- Confirmed/Expired/Cancelled thi hold khong con y nghia -> khong rang buoc.
    CONSTRAINT CHK_Booking_PendingHoldDates CHECK (
        BookingStatus <> 'Pending'
        OR (HoldStartDatetime IS NOT NULL AND HoldExpiryDatetime IS NOT NULL)
    ),
    CONSTRAINT CHK_Booking_Subtotal CHECK (SubtotalAmount >= 0),
    CONSTRAINT CHK_Booking_FinalAmount CHECK (FinalAmount >= 0),
    CONSTRAINT CHK_Booking_Timestamps CHECK (
        (CASE WHEN ConfirmedTimestamp IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN CancelledTimestamp IS NOT NULL THEN 1 ELSE 0 END +
         CASE WHEN ExpiredTimestamp IS NOT NULL THEN 1 ELSE 0 END) <= 1
    )
);
