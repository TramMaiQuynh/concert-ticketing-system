CREATE TABLE DiscountCode (
    DiscountCodeID INT IDENTITY(1,1) NOT NULL,
    PromotionID INT NOT NULL,
    CodeValue VARCHAR(64) NOT NULL,
    CodeStatus VARCHAR(32) NOT NULL,
    ValidFromDatetime DATETIME2(7),
    ValidToDatetime DATETIME2(7),
    CONSTRAINT PK_DiscountCode PRIMARY KEY CLUSTERED (DiscountCodeID),
    CONSTRAINT FK_DiscountCode_Promotion FOREIGN KEY (PromotionID) REFERENCES Promotion(PromotionID),
    CONSTRAINT UQ_DiscountCode_Value UNIQUE (PromotionID, CodeValue),
    CONSTRAINT CHK_DiscountCode_Status CHECK (CodeStatus IN ('Active', 'Expired', 'Disabled'))
);
