CREATE TABLE DiscountCode (
    DiscountCodeID INT IDENTITY(1,1) NOT NULL,
    PromotionID INT NOT NULL,
    CodeValue VARCHAR(64) NOT NULL,
    CodeStatus VARCHAR(32) NOT NULL,
    ValidFromDatetime DATETIME2(7),
    ValidToDatetime DATETIME2(7),
    GlobalUsageLimit INT,
    PerCustomerUsageLimit INT,
    ReservedUsageCount INT NOT NULL DEFAULT 0,
    ConsumedUsageCount INT NOT NULL DEFAULT 0,
    CONSTRAINT PK_DiscountCode PRIMARY KEY CLUSTERED (DiscountCodeID),
    CONSTRAINT FK_DiscountCode_Promotion FOREIGN KEY (PromotionID) REFERENCES Promotion(PromotionID),
    CONSTRAINT UQ_DiscountCode_Value UNIQUE (PromotionID, CodeValue),
    -- Khoa thay the (PromotionID, DiscountCodeID) de lam muc tieu cho FK composite
    -- tu BookingPromotionApplication: ep DiscountCodeID khi duoc apply vao Booking
    -- PHAI thuoc dung PromotionID cua hang (chong dung code cua promotion khac).
    CONSTRAINT UQ_DiscountCode_PromotionCodeID UNIQUE (PromotionID, DiscountCodeID),
    CONSTRAINT CHK_DiscountCode_Status CHECK (CodeStatus IN ('Active', 'Expired', 'Disabled')),
    CONSTRAINT CHK_DiscountCode_ValidDates CHECK (
        ValidFromDatetime IS NULL OR ValidToDatetime IS NULL OR ValidToDatetime >= ValidFromDatetime
    ),
    CONSTRAINT CHK_DiscountCode_GlobalLimit CHECK (GlobalUsageLimit IS NULL OR GlobalUsageLimit > 0),
    CONSTRAINT CHK_DiscountCode_PerCustomerLimit CHECK (PerCustomerUsageLimit IS NULL OR PerCustomerUsageLimit > 0),
    CONSTRAINT CHK_DiscountCode_UsageCounts CHECK (
        ReservedUsageCount >= 0 AND ConsumedUsageCount >= 0
        AND (GlobalUsageLimit IS NULL OR ReservedUsageCount + ConsumedUsageCount <= GlobalUsageLimit)
    )
);
