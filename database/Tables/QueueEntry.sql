CREATE TABLE QueueEntry (
    QueueEntryID INT IDENTITY(1,1) NOT NULL,
    QueueID INT NOT NULL,
    CustomerUserID INT NOT NULL,
    JoinedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    AdmissionPosition INT,
    QueueStatus VARCHAR(32) NOT NULL,
    AdmissionTimestamp DATETIME2(7),
    ExitTimestamp DATETIME2(7),
    AdmissionExpiryTimestamp DATETIME2(7),
    IsDeleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_QueueEntry PRIMARY KEY CLUSTERED (QueueEntryID),
    CONSTRAINT FK_QueueEntry_Queue FOREIGN KEY (QueueID) REFERENCES Queue(QueueID),
    CONSTRAINT FK_QueueEntry_Customer FOREIGN KEY (CustomerUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT CHK_QueueEntry_Status CHECK (QueueStatus IN ('Waiting', 'Admitted', 'Expired', 'Exited', 'Cancelled'))
);
