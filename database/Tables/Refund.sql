CREATE TABLE Refund (
    RefundID INT IDENTITY(1,1) NOT NULL,
    PaymentID INT NOT NULL,
    RefundStatus VARCHAR(32) NOT NULL,
    RefundAmount DECIMAL(18,0) NOT NULL,
    RefundReason NVARCHAR(500),
    RefundRequestTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    RefundConfirmationTimestamp DATETIME2(7),
    RefundReference VARCHAR(64),
    CONSTRAINT PK_Refund PRIMARY KEY CLUSTERED (RefundID),
    CONSTRAINT FK_Refund_Payment FOREIGN KEY (PaymentID) REFERENCES Payment(PaymentID),
    CONSTRAINT CHK_Refund_Status CHECK (RefundStatus IN ('Pending', 'Confirmed', 'Failed', 'Cancelled')),
    CONSTRAINT CHK_Refund_Amount CHECK (RefundAmount >= 0)
);
