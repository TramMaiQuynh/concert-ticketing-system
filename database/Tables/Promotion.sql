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
    MaxApplicableQuantity INT,
    MaxDiscountAmount DECIMAL(18,0),
    CONSTRAINT PK_Promotion PRIMARY KEY CLUSTERED (PromotionID),
    CONSTRAINT FK_Promotion_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    -- Domain chi gom cac trang thai do NGUOI VAN HANH quyet dinh.
    -- 'Expired' da bi loai bo: het han la thuoc tinh DAN XUAT tu EndDatetime,
    -- khong phai mot trang thai luu tru. Giu ca hai la vi pham nguyen tac
    -- "mot su that mot noi" (BR50d): mot Promotion co the vua PromotionStatus
    -- = 'Active' vua qua EndDatetime, va khong cach nao biet ban ghi nao dung.
    -- Hieu luc theo thoi gian duoc quyet dinh boi [StartDatetime, EndDatetime)
    -- tai sp_ApplyPromotion, TRG_PromotionValidity va VW_ActivePromotions.
    CONSTRAINT CHK_Promotion_Status CHECK (PromotionStatus IN ('Draft', 'Active', 'Disabled')),
    CONSTRAINT CHK_Promotion_DiscountType CHECK (DiscountType IN ('Percentage', 'Fixed Amount')),
    CONSTRAINT CHK_Promotion_Dates CHECK (EndDatetime > StartDatetime),
    -- Phong thu: DiscountValue phai > 0; UsageLimit neu co phai > 0
    CONSTRAINT CHK_Promotion_DiscountValue CHECK (DiscountValue > 0),
    CONSTRAINT CHK_Promotion_UsageLimit CHECK (UsageLimit IS NULL OR UsageLimit > 0),
    CONSTRAINT CHK_Promotion_MaxQuantity CHECK (MaxApplicableQuantity IS NULL OR MaxApplicableQuantity > 0),
    CONSTRAINT CHK_Promotion_MaxDiscount CHECK (MaxDiscountAmount IS NULL OR MaxDiscountAmount > 0)
);
