CREATE TABLE AuditRecord (
    AuditID INT IDENTITY(1,1) NOT NULL,
    ActorUserID INT NOT NULL,
    EventType VARCHAR(64) NOT NULL,
    EntityType VARCHAR(64) NOT NULL,
    EntityID VARCHAR(64) NOT NULL,
    Action VARCHAR(32) NOT NULL,
    EventTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    PreviousValue NVARCHAR(MAX),
    NewValue NVARCHAR(MAX),
    TransactionReference VARCHAR(64),
    CONSTRAINT PK_AuditRecord PRIMARY KEY CLUSTERED (AuditID),
    CONSTRAINT FK_AuditRecord_Actor FOREIGN KEY (ActorUserID) REFERENCES UserAccount(UserID)
);
