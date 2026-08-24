CREATE TABLE Payment (
    PaymentID INT IDENTITY(1,1) NOT NULL,
    BookingID INT NOT NULL,
    PaymentStatus VARCHAR(32) NOT NULL,
    Amount DECIMAL(18,0) NOT NULL,
    Currency CHAR(3) NOT NULL DEFAULT 'VND',
    PaymentReference VARCHAR(64) NOT NULL,
    PaymentRequestTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    ConfirmationTimestamp DATETIME2(7),
    FailureTimestamp DATETIME2(7),
    ProviderReference VARCHAR(64),
    CONSTRAINT PK_Payment PRIMARY KEY CLUSTERED (PaymentID),
    CONSTRAINT FK_Payment_Booking FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT UQ_Payment_Idempotency UNIQUE (BookingID, PaymentReference),
    CONSTRAINT CHK_Payment_Status CHECK (PaymentStatus IN ('Pending', 'Confirmed', 'Failed', 'Refunded')),
    CONSTRAINT CHK_Payment_Amount CHECK (Amount >= 0),
    CONSTRAINT CHK_Payment_Currency CHECK (Currency = 'VND')
);

CREATE UNIQUE NONCLUSTERED INDEX UIX_Payment_ConfirmedPerBooking 
ON Payment (BookingID)
WHERE PaymentStatus = 'Confirmed';
