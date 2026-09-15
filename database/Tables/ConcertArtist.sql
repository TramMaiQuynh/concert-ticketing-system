-- Nghệ sĩ và concert là quan hệ nhiều-nhiều: một chương trình có thể có nhiều
-- nghệ sĩ, và một nghệ sĩ có thể tham gia nhiều chương trình. ArtistOrder giữ
-- thứ tự được công bố ở trang concert, không dùng thứ tự ngầm của ID.
CREATE TABLE ConcertArtist (
    ConcertID   INT      NOT NULL,
    ArtistID    INT      NOT NULL,
    ArtistOrder INT NOT NULL,

    CONSTRAINT PK_ConcertArtist PRIMARY KEY CLUSTERED (ConcertID, ArtistID),
    CONSTRAINT UQ_ConcertArtist_Order UNIQUE (ConcertID, ArtistOrder),
    CONSTRAINT FK_ConcertArtist_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT FK_ConcertArtist_Artist FOREIGN KEY (ArtistID) REFERENCES Artist(ArtistID),
    CONSTRAINT CHK_ConcertArtist_Order CHECK (ArtistOrder > 0)
);
GO
