CREATE TABLE TicketCategory (
    TicketCategoryID INT IDENTITY(1,1) NOT NULL,
    ConcertID INT NOT NULL,
    CategoryName NVARCHAR(255) NOT NULL,
    CategoryDescription NVARCHAR(500),
    BasePrice DECIMAL(18,0) NOT NULL,
    CategoryStatus VARCHAR(32) NOT NULL,
    CONSTRAINT PK_TicketCategory PRIMARY KEY CLUSTERED (TicketCategoryID),
    CONSTRAINT FK_TicketCategory_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT UQ_TicketCategory_Composite UNIQUE (ConcertID, TicketCategoryID),
    -- Domain per §18.4.1: Active (đang bán), Inactive (đã ngưng)
    CONSTRAINT CHK_Category_Status CHECK (CategoryStatus IN ('Active', 'Inactive')),
    CONSTRAINT CHK_Category_BasePrice CHECK (BasePrice >= 0)
);
