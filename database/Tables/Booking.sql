CREATE TABLE Booking (
    BookingID INT IDENTITY(1,1) NOT NULL,
    CustomerUserID INT NOT NULL,
    ConcertID INT NOT NULL,
    BookingStatus VARCHAR(32) NOT NULL,
    HoldStartDatetime DATETIME2(7),
    HoldExpiryDatetime DATETIME2(7),
    SubtotalAmount DECIMAL(18,0) NOT NULL,
    FinalAmount DECIMAL(18,0) NOT NULL,
    CreatedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    ConfirmedTimestamp DATETIME2(7),
    CancelledTimestamp DATETIME2(7),
    ExpiredTimestamp DATETIME2(7),
    CONSTRAINT PK_Booking PRIMARY KEY CLUSTERED (BookingID),
    CONSTRAINT FK_Booking_Customer FOREIGN KEY (CustomerUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_Booking_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT CHK_Booking_Status CHECK (BookingStatus IN ('Pending', 'Confirmed', 'Expired', 'Cancelled')),
    CONSTRAINT CHK_Booking_HoldDates CHECK (HoldExpiryDatetime > HoldStartDatetime),
    -- BR16 (§12.9.1): Booking Pending = Temporary Hold dang hieu luc
    -- -> bat buoc co HoldStartDatetime va HoldExpiryDatetime.
    -- Confirmed/Expired/Cancelled thi hold khong con y nghia -> khong rang buoc.
    CONSTRAINT CHK_Booking_PendingHoldDates CHECK (
        BookingStatus <> 'Pending'
        OR (HoldStartDatetime IS NOT NULL AND HoldExpiryDatetime IS NOT NULL)
    ),
    CONSTRAINT CHK_Booking_Subtotal CHECK (SubtotalAmount >= 0),
    CONSTRAINT CHK_Booking_FinalAmount CHECK (FinalAmount >= 0),
    -- Bat bien thoi diem <-> trang thai (thay cho rang buoc loai tru cu).
    -- Rang buoc cu "toi da 1 trong 3 timestamp" la SAI voi state machine §10.1:
    -- Confirmed -> Cancelled la chuyen doi hop le, nen mot Booking da xac nhan roi
    -- bi huy PHAI giu ca ConfirmedTimestamp lan CancelledTimestamp - hai su kien
    -- deu that su xay ra. Rang buoc cu ep phai danh mat lich su, va do chinh la
    -- ly do cac SP huy khong dam ghi CancelledTimestamp.
    -- Bat bien dung: moi trang thai ket thuc PHAI co dau thoi gian cua chinh no;
    -- Expired va Cancelled loai tru nhau (hai nhanh terminal khac nhau);
    -- Pending thi chua co bat ky dau thoi gian ket thuc nao.
    CONSTRAINT CHK_Booking_TimestampCoherence CHECK (
            (BookingStatus <> 'Confirmed' OR ConfirmedTimestamp IS NOT NULL)
        AND (BookingStatus <> 'Expired'   OR ExpiredTimestamp   IS NOT NULL)
        AND (BookingStatus <> 'Cancelled' OR CancelledTimestamp IS NOT NULL)
        AND (ExpiredTimestamp IS NULL OR CancelledTimestamp IS NULL)
        AND (BookingStatus <> 'Pending'
             OR (ConfirmedTimestamp IS NULL AND CancelledTimestamp IS NULL AND ExpiredTimestamp IS NULL))
    )
);
