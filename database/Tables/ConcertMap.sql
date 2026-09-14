-- ============================================================
-- ConcertMap (StagePass)
--
-- Root một-một với Concert, giữ identity của "sơ đồ ghế của concert này" tách
-- biệt khỏi lịch sử phiên bản của nó (ConcertMapRevision). Bảng riêng thay vì
-- một cột trên Concert vì mỗi Concert có NHIỀU revision theo thời gian, và
-- ConcertMap là điểm neo ổn định để trỏ tới "revision nào đang dùng để bán",
-- không phải để lưu hình học trực tiếp.
-- ============================================================
CREATE TABLE ConcertMap (
    ConcertMapID INT IDENTITY(1,1) NOT NULL,
    ConcertID    INT NOT NULL,

    CONSTRAINT PK_ConcertMap PRIMARY KEY CLUSTERED (ConcertMapID),
    CONSTRAINT FK_ConcertMap_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    -- Một Concert chỉ có một ConcertMap — nhiều revision nằm bên dưới nó, không
    -- phải nhiều ConcertMap song song.
    CONSTRAINT UQ_ConcertMap_Concert UNIQUE (ConcertID)
);
