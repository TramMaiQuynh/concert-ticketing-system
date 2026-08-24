CREATE TABLE Role (
    RoleID INT IDENTITY(1,1) NOT NULL,
    RoleName NVARCHAR(255) NOT NULL,
    RoleDescription NVARCHAR(500),
    RoleStatus VARCHAR(32) NOT NULL,
    CONSTRAINT PK_Role PRIMARY KEY CLUSTERED (RoleID),
    CONSTRAINT UQ_Role_RoleName UNIQUE (RoleName),
    CONSTRAINT CHK_Role_Status CHECK (RoleStatus IN ('Active', 'Inactive'))
);
