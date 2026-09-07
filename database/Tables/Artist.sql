CREATE TABLE Artist (
    ArtistID INT IDENTITY(1,1) NOT NULL,
    ArtistName NVARCHAR(255) NOT NULL,
    ArtistDescription NVARCHAR(500),
    -- BR50e: Artist bi Concert lich su tham chieu nen khong the Hard Delete.
    -- Retired = ngung su dung cho Concert moi, du lieu cu van truy van binh thuong.
    ArtistStatus VARCHAR(32) NOT NULL CONSTRAINT DF_Artist_Status DEFAULT 'Active',
    CONSTRAINT PK_Artist PRIMARY KEY CLUSTERED (ArtistID),
    CONSTRAINT CHK_Artist_Status CHECK (ArtistStatus IN ('Active', 'Retired'))
);
