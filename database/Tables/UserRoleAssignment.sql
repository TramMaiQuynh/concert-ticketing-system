CREATE TABLE UserRoleAssignment (
    UserID INT NOT NULL,
    RoleID INT NOT NULL,
    AssignedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    AssignmentStatus VARCHAR(32) NOT NULL,
    CONSTRAINT PK_UserRoleAssignment PRIMARY KEY CLUSTERED (UserID, RoleID),
    CONSTRAINT FK_UserRoleAssignment_User FOREIGN KEY (UserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_UserRoleAssignment_Role FOREIGN KEY (RoleID) REFERENCES Role(RoleID),
    -- Domain per §18.4.1: Active (gán hiệu lực), Revoked (đã thu hồi theo BR52)
    CONSTRAINT CHK_Assignment_Status CHECK (AssignmentStatus IN ('Active', 'Revoked'))
);
