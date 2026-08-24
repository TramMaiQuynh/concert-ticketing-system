CREATE TABLE BookingPromotionApplication (
    BookingID INT NOT NULL,
    PromotionID INT NOT NULL,
    DiscountCodeID INT,
    DiscountAmount DECIMAL(18,0) NOT NULL,
    AppliedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_BookingPromotionApplication PRIMARY KEY CLUSTERED (BookingID, PromotionID),
    CONSTRAINT FK_BPA_Booking FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BPA_Promotion FOREIGN KEY (PromotionID) REFERENCES Promotion(PromotionID),
    CONSTRAINT FK_BPA_DiscountCode FOREIGN KEY (DiscountCodeID) REFERENCES DiscountCode(DiscountCodeID),
    CONSTRAINT CHK_BPA_DiscountAmount CHECK (DiscountAmount >= 0)
);
