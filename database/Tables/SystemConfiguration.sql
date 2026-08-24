CREATE TABLE SystemConfiguration (
    ConfigurationID INT IDENTITY(1,1) NOT NULL,
    ConfigurationKey VARCHAR(64) NOT NULL,
    ConfigurationValue NVARCHAR(500) NOT NULL,
    CONSTRAINT PK_SystemConfiguration PRIMARY KEY CLUSTERED (ConfigurationID),
    CONSTRAINT UQ_SystemConfiguration_Key UNIQUE (ConfigurationKey)
);
