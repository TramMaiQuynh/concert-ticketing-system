CREATE TABLE Queue (
    QueueID INT IDENTITY(1,1) NOT NULL,
    ConcertID INT NOT NULL,
    QueueStatus VARCHAR(32) NOT NULL,
    AdmissionCapacity INT NOT NULL,
    FairAccessPolicy VARCHAR(32) NOT NULL,
    IsDeleted BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_Queue PRIMARY KEY CLUSTERED (QueueID),
    CONSTRAINT UQ_Queue_Concert UNIQUE (ConcertID),
    CONSTRAINT FK_Queue_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT CHK_Queue_Status CHECK (QueueStatus IN ('Open', 'Closed')),
    CONSTRAINT CHK_Queue_Capacity CHECK (AdmissionCapacity > 0),
    CONSTRAINT CHK_Queue_Policy CHECK (FairAccessPolicy IN ('FIFO', 'RANDOM'))
);
