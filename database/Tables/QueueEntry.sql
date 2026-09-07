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
    CONSTRAINT PK_QueueEntry PRIMARY KEY CLUSTERED (QueueEntryID),
    CONSTRAINT FK_QueueEntry_Queue FOREIGN KEY (QueueID) REFERENCES Queue(QueueID),
    CONSTRAINT FK_QueueEntry_Customer FOREIGN KEY (CustomerUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT CHK_QueueEntry_Status CHECK (QueueStatus IN ('Waiting', 'Admitted', 'Expired', 'Exited', 'Cancelled'))
);

-- BR46/QI03: mot Customer chi duoc co TOI DA MOT QueueEntry dang hoat dong
-- (Waiting hoac Admitted) trong mot Queue. Kiem tra bang IF EXISTS trong
-- sp_JoinQueue KHONG du: o muc READ COMMITTED hai request dong thoi deu doc
-- thay "chua co" roi cung INSERT -> khach hang nhan hai suat xep hang, tuc la
-- bo qua co che admission chi bang cach ban request nhanh hon (dung dieu BR46
-- cam). Doi xung voi UIX_WaitlistEntry_ActivePerCustomer tren WaitlistEntry.
CREATE UNIQUE NONCLUSTERED INDEX UIX_QueueEntry_ActivePerCustomer
ON QueueEntry (QueueID, CustomerUserID)
WHERE QueueStatus IN ('Waiting', 'Admitted');
