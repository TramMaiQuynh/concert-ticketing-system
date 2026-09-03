CREATE TABLE CheckinStaffAssignment (
    UserID INT NOT NULL,
    ConcertID INT NOT NULL,
    AssignedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    AssignmentStatus VARCHAR(32) NOT NULL DEFAULT 'Active',
    CONSTRAINT PK_CheckinStaffAssignment PRIMARY KEY CLUSTERED (UserID, ConcertID),
    CONSTRAINT FK_CheckinStaffAssignment_User FOREIGN KEY (UserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_CheckinStaffAssignment_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT CHK_StaffAssignment_Status CHECK (AssignmentStatus IN ('Active', 'Revoked'))
);
