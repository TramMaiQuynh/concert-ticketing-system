CREATE TABLE Queue (
    QueueID INT IDENTITY(1,1) NOT NULL,
    ConcertID INT NOT NULL,
    QueueStatus VARCHAR(32) NOT NULL,
    AdmissionCapacity INT NOT NULL,
    FairAccessPolicy VARCHAR(32) NOT NULL,
    -- FR64a/BR47b: booking_ttl duoc cau hinh THEO CONCERT, khong phai mot hang so
    -- toan cuc - moi su kien co do "nong" khac nhau nen thoi gian cho khach hoan tat
    -- Booking cung khac nhau. NULL = ke thua mac dinh he thong
    -- (SystemConfiguration.Queue_Admission_Validity).
    AdmissionValiditySeconds INT NULL,
    CONSTRAINT PK_Queue PRIMARY KEY CLUSTERED (QueueID),
    CONSTRAINT UQ_Queue_Concert UNIQUE (ConcertID),
    CONSTRAINT FK_Queue_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT CHK_Queue_Status CHECK (QueueStatus IN ('Open', 'Closed')),
    CONSTRAINT CHK_Queue_Capacity CHECK (AdmissionCapacity > 0),
    CONSTRAINT CHK_Queue_Policy CHECK (FairAccessPolicy IN ('FIFO', 'RANDOM')),
    CONSTRAINT CHK_Queue_AdmissionValidity CHECK (AdmissionValiditySeconds IS NULL OR AdmissionValiditySeconds > 0)
);
