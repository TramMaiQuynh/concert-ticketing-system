CREATE TABLE UserAccount (
    UserID INT IDENTITY(1,1) NOT NULL,
    Username VARCHAR(64) NOT NULL,
    AccountStatus VARCHAR(32) NOT NULL,
    CreatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    UpdatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    Email NVARCHAR(255),
    DisplayName NVARCHAR(255),
    PasswordHash NVARCHAR(255),
    CONSTRAINT PK_UserAccount PRIMARY KEY CLUSTERED (UserID),
    CONSTRAINT UQ_UserAccount_Username UNIQUE (Username),
    CONSTRAINT CHK_UserAccount_Status CHECK (AccountStatus IN ('Active', 'Locked', 'Disabled'))
);
