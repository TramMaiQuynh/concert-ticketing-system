CREATE TABLE BookingPromotionApplication (
    BookingID INT NOT NULL,
    PromotionID INT NOT NULL,
    DiscountCodeID INT,
    DiscountAmount DECIMAL(18,0) NOT NULL,
    AppliedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_BookingPromotionApplication PRIMARY KEY CLUSTERED (BookingID, PromotionID),
    CONSTRAINT FK_BPA_Booking FOREIGN KEY (BookingID) REFERENCES Booking(BookingID),
    CONSTRAINT FK_BPA_Promotion FOREIGN KEY (PromotionID) REFERENCES Promotion(PromotionID),
    -- FK composite thay cho FK don tren (DiscountCodeID): neu DiscountCodeID co gia tri,
    -- no PHAI thuoc dung PromotionID cua hang -> ep dung rang buoc nhat quan
    -- giua Promotion/Coupon khi apply (DR/FK-03). NULL -> khong enforce, dung cho
    -- Promotion khong yeu cau code. Muc tieu: DiscountCode(PromotionID, DiscountCodeID),
    -- duoc dao boi UQ_DiscountCode_PromotionCodeID tren bang DiscountCode.
    CONSTRAINT FK_BPA_DiscountCode FOREIGN KEY (PromotionID, DiscountCodeID)
        REFERENCES DiscountCode(PromotionID, DiscountCodeID),
    CONSTRAINT CHK_BPA_DiscountAmount CHECK (DiscountAmount >= 0)
);
