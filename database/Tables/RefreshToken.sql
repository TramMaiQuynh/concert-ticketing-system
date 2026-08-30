CREATE TABLE RefreshToken (
    TokenID        INT IDENTITY(1,1) NOT NULL,
    UserID         INT NOT NULL,
    -- SHA-256 hex = đúng 64 ký tự, xác nhận từ UserRepository.ComputeSha256Hex()
    TokenHash      VARCHAR(64) NOT NULL,
    ExpiryDatetime DATETIME2(7) NOT NULL,
    IsRevoked      BIT NOT NULL DEFAULT 0,
    CONSTRAINT PK_RefreshToken PRIMARY KEY CLUSTERED (TokenID),
    -- UNIQUE trên TokenHash để lookup O(log n) và đảm bảo không trùng hash
    CONSTRAINT UQ_RefreshToken_Hash UNIQUE (TokenHash),
    CONSTRAINT FK_RefreshToken_User FOREIGN KEY (UserID) REFERENCES UserAccount(UserID)
);

-- Index hỗ trợ cleanup job (xóa token đã hết hạn) — tránh table scan
CREATE NONCLUSTERED INDEX IX_RefreshToken_Expiry
ON RefreshToken (ExpiryDatetime)
WHERE IsRevoked = 0;
