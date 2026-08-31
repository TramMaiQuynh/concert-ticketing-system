CREATE TABLE Promotion (
    PromotionID INT IDENTITY(1,1) NOT NULL,
    ConcertID INT NOT NULL,
    PromotionName NVARCHAR(255) NOT NULL,
    PromotionDescription NVARCHAR(500),
    DiscountType VARCHAR(32) NOT NULL,
    DiscountValue DECIMAL(18,0) NOT NULL,
    StartDatetime DATETIME2(7) NOT NULL,
    EndDatetime DATETIME2(7) NOT NULL,
    PromotionStatus VARCHAR(32) NOT NULL,
    UsageLimit INT,
    CodeRequiredFlag BIT NOT NULL,
    CONSTRAINT PK_Promotion PRIMARY KEY CLUSTERED (PromotionID),
    CONSTRAINT FK_Promotion_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT CHK_Promotion_Status CHECK (PromotionStatus IN ('Draft', 'Active', 'Expired', 'Disabled')),
    CONSTRAINT CHK_Promotion_Dates CHECK (EndDatetime > StartDatetime),
    -- Phong thu: DiscountValue phai > 0; UsageLimit neu co phai > 0
    CONSTRAINT CHK_Promotion_DiscountValue CHECK (DiscountValue > 0),
    CONSTRAINT CHK_Promotion_UsageLimit CHECK (UsageLimit IS NULL OR UsageLimit > 0)
);
