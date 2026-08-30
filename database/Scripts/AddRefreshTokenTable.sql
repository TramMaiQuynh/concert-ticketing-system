-- =============================================================================
-- Migration: Thêm bảng RefreshToken để lưu Refresh Token phía Server
--
-- Lý do thiết kế:
--   - Refresh Token là state bảo mật quan trọng → phải lưu bền vững trong DB,
--     không dùng Redis (Redis có eviction policy allkeys-lru, có thể xóa token).
--   - Chỉ lưu HASH (SHA-256) của token, không lưu raw value.
--     Raw value chỉ tồn tại trong response / HttpOnly Cookie phía client.
--   - IsRevoked cho phép thu hồi từng session cụ thể (logout 1 thiết bị).
-- =============================================================================

CREATE TABLE RefreshToken (
    TokenID        INT IDENTITY(1,1) NOT NULL,
    UserID         INT NOT NULL,
    TokenHash      VARCHAR(64)  NOT NULL,   -- SHA-256 hex = 64 ký tự ASCII
    ExpiryDatetime DATETIME2(7) NOT NULL,
    IsRevoked      BIT          NOT NULL DEFAULT 0,
    CreatedAt      DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    CONSTRAINT PK_RefreshToken         PRIMARY KEY CLUSTERED (TokenID),
    CONSTRAINT UQ_RefreshToken_Hash    UNIQUE (TokenHash),
    CONSTRAINT FK_RefreshToken_User    FOREIGN KEY (UserID)
        REFERENCES UserAccount(UserID)
);

-- Index để tìm nhanh theo TokenHash (lookup khi client gửi refresh request)
CREATE NONCLUSTERED INDEX IX_RefreshToken_Hash
    ON RefreshToken (TokenHash)
    WHERE IsRevoked = 0;

-- Index để dọn dẹp token hết hạn (maintenance job nếu cần)
CREATE NONCLUSTERED INDEX IX_RefreshToken_Expiry
    ON RefreshToken (ExpiryDatetime)
    WHERE IsRevoked = 0;

-- Phân quyền cho api_service
GRANT SELECT ON dbo.RefreshToken TO api_service;
GRANT INSERT ON dbo.RefreshToken TO api_service;
GRANT UPDATE ON dbo.RefreshToken TO api_service;
-- Không cấp DELETE — thu hồi bằng IsRevoked=1, không xóa (giữ audit trail)
