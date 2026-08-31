-- =============================================================================
-- Migration: Thêm bảng RefreshToken để lưu Refresh Token phía Server.
--
-- Lý do thiết kế:
--   - Refresh Token là state bảo mật quan trọng → phải lưu bền vững trong DB,
--     không dùng Redis (Redis có eviction policy allkeys-lru, có thể xóa token).
--   - Chỉ lưu HASH (SHA-256) của token, không lưu raw value.
--     Raw value chỉ tồn tại trong response / HttpOnly Cookie phía client.
--   - IsRevoked cho phép thu hồi từng session cụ thể (logout 1 thiết bị).
--
-- Script này là MIGRATION cho cơ sở dữ liệu đã tồn tại trước khi RefreshToken
-- được đưa vào deploy chuẩn (Tables/RefreshToken.sql, PHASE 1 cua deploy.ps1).
-- Do bảng nay da duoc deploy san trong luong chuan, toan bo noi dung phai
-- IDEMPOTENT (an toan chay nhieu lan):
--   - Tao bang chi khi chua ton tai.
--   - Schema KHOP TUYET DOI voi Tables/RefreshToken.sql (chong schema drift;
--     khong tao cot/index/constraint thua chi ton tai o ban migration cu).
-- =============================================================================

USE [ConcertTicketingDB];
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID(N'dbo.RefreshToken', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.RefreshToken (
        TokenID        INT IDENTITY(1,1) NOT NULL,
        UserID         INT NOT NULL,
        -- SHA-256 hex = đúng 64 ký tự, xác nhận từ UserRepository.ComputeSha256Hex()
        TokenHash      VARCHAR(64)  NOT NULL,
        ExpiryDatetime DATETIME2(7) NOT NULL,
        IsRevoked      BIT          NOT NULL DEFAULT 0,
        CONSTRAINT PK_RefreshToken      PRIMARY KEY CLUSTERED (TokenID),
        CONSTRAINT UQ_RefreshToken_Hash UNIQUE (TokenHash),
        CONSTRAINT FK_RefreshToken_User FOREIGN KEY (UserID) REFERENCES dbo.UserAccount(UserID)
    );
END
GO

-- Index hỗ trợ cleanup job (xóa token đã hết hạn) — tránh table scan.
-- Dung cau truc index giong Tables/RefreshToken.sql de 2 luong tao engine
-- (deploy chuan vs migration) luon tao ra cung mot schema.
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE  object_id = OBJECT_ID(N'dbo.RefreshToken')
      AND  name      = N'IX_RefreshToken_Expiry'
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_RefreshToken_Expiry
        ON dbo.RefreshToken (ExpiryDatetime)
        WHERE IsRevoked = 0;
END
GO

-- Phân quyền cho api_service (idempotent — GRANT an toan chay lai nhieu lan).
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'api_service')
BEGIN
    GRANT SELECT ON dbo.RefreshToken TO api_service;
    GRANT INSERT ON dbo.RefreshToken TO api_service;
    GRANT UPDATE ON dbo.RefreshToken TO api_service;
    -- Không cấp DELETE — thu hồi bằng IsRevoked=1, không xóa (giữ audit trail)
END
GO