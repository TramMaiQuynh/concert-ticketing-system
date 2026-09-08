CREATE TABLE BookingPromotionApplication (
    BookingID INT NOT NULL,
    PromotionID INT NOT NULL,
    DiscountCodeID INT,
    ApplicationOrder INT NOT NULL,
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
    CONSTRAINT CHK_BPA_DiscountAmount CHECK (DiscountAmount >= 0),
    -- R23: khong duoc trung thu tu ap dung trong cung mot Booking.
    -- ApplicationOrder la gia tri DAN XUAT (BR36d/PI06): sp_ApplyPromotion danh so
    -- lai ca chuoi theo PromotionID tang dan sau moi lan ap dung. Rang buoc nay bien
    -- "1..N khong trung" thanh bat bien duoc tang du lieu ep buoc, thay vi mot tinh
    -- chat chi dung nho thu tuc viet dung. Viec danh so lai la MOT lenh UPDATE
    -- set-based nen SQL Server chi kiem tra khi lenh ket thuc - mot hoan vi
    -- (vi du 1,2 -> 2,1) khong sinh vi pham trung gian.
    CONSTRAINT UQ_BPA_BookingApplicationOrder UNIQUE (BookingID, ApplicationOrder)
);
