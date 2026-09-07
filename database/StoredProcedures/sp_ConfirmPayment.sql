-- ============================================================
-- sp_ConfirmPayment (BP6 / BR22-BR27 / FR24-FR30)
-- Thuat toan 5 buoc xu ly thanh toan + Race condition handling:
--   1. UPDATE Payment -> Confirmed vo dieu kien (ghi nhan su that tai chinh).
--   2. SELECT Booking voi UPDLOCK de tuan tu hoa.
--   2b. Doi chieu Payment.Amount voi Booking.FinalAmount; neu lech -> auto Refund.
--   3. Thu xac lap IsBookingConfirmingPayment=1; neu vi pham UIX -> auto Refund.
--   4. Kiem tra Booking Pending & con han (HoldExpiry); neu het han -> auto Refund.
--   5. Phat hanh Ticket, chuyen Booking -> Confirmed, EventSeat -> Booked.
--
-- BAT BIEN XUYEN SUOT: sau buoc 1, tien da duoc cong thanh toan thu. Moi nhanh
-- khong the hoan tat don hang deu phai KET THUC BANG MOT REFUND, khong nhanh nao
-- duoc ROLLBACK bo su that tai chinh da ghi.
-- ============================================================
DROP PROCEDURE IF EXISTS dbo.sp_ConfirmPayment;
GO
CREATE PROCEDURE dbo.sp_ConfirmPayment
(
    @BookingID         INT,
    @PaymentID         INT,
    @ProviderReference VARCHAR(64) = NULL,
    -- KET QUA nghiep vu cua lan goi nay. Bat buoc phai co: sau khi nhanh lech so tien
    -- chuyen tu "nem loi" sang "tu dong hoan tien", SP KHONG con nem loi cho phan lon
    -- cac tinh huong bat thuong - no COMMIT thanh cong nhung don hang KHONG duoc xac
    -- nhan. Neu caller chi nhin vao "co exception hay khong" thi se bao voi cong thanh
    -- toan va voi khach rang thanh toan da thanh cong trong khi khach khong he co ve.
    -- Gia tri:
    --   'Confirmed'                        - da xac nhan Booking va phat hanh ve
    --   'AlreadyConfirmed'                 - callback lap lai, Payment nay dang hieu luc
    --   'AlreadyRefunded'                  - callback lap lai, Payment nay da bi hoan truoc do
    --   'AutoRefunded_AmountMismatch'      - so tien khong khop tong don -> da tao Refund
    --   'AutoRefunded_DuplicatePayment'    - Booking da co Payment hieu luc khac -> da tao Refund
    --   'AutoRefunded_BookingNotPending'   - Booking het han/khong con cho -> da tao Refund
    @Outcome           VARCHAR(48) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @Outcome = NULL;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- CRIT-14: Dung AppLock theo Booking de dam bao tuan tu, tranh deadlock khi update
        DECLARE @LockResource NVARCHAR(128) = 'ConfirmPayment_Booking_' + CAST(@BookingID AS NVARCHAR(20));
        DECLARE @LockResult INT;
        EXEC @LockResult = sp_getapplock
            @Resource = @LockResource,
            @LockMode = 'Exclusive',
            @LockOwner = 'Transaction',
            @LockTimeout = 5000;

        IF @LockResult < 0
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52006, 'sp_ConfirmPayment: He thong dang xu ly yeu cau cho Booking nay.', 1;
        END

        -- 1. Kiem tra Payment va Idempotency (CRIT-10)
        DECLARE @PaymentAmount DECIMAL(18,0);
        DECLARE @CustomerID INT;
        DECLARE @PaymentStatus VARCHAR(32);

        DECLARE @IsEffective BIT;

        SELECT @PaymentAmount = Amount,
               @PaymentStatus = PaymentStatus,
               @IsEffective   = IsBookingConfirmingPayment
        FROM   Payment WITH (UPDLOCK)
        WHERE  PaymentID = @PaymentID AND BookingID = @BookingID;

        IF @PaymentAmount IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52001, 'sp_ConfirmPayment: Payment khong ton tai hoac khong thuoc Booking nay.', 1;
        END

        -- CRIT-10: Idempotency check.
        -- Phan biet hai tinh huong deu co PaymentStatus = 'Confirmed':
        --   IsBookingConfirmingPayment = 1 -> Payment nay chinh la Payment hieu luc cua
        --      Booking, don hang da hoan tat.
        --   IsBookingConfirmingPayment = 0 -> Payment da duoc ghi nhan nhung KHONG duoc
        --      dung de xac nhan Booking (mot trong ba nhanh tu dong hoan tien o duoi da
        --      chay truoc do). Bao 'AlreadyConfirmed' cho truong hop nay se noi doi.
        IF @PaymentStatus = 'Confirmed'
        BEGIN
            SET @Outcome = CASE WHEN @IsEffective = 1 THEN 'AlreadyConfirmed' ELSE 'AlreadyRefunded' END;
            COMMIT TRANSACTION;
            RETURN;
        END

        UPDATE Payment
        SET    PaymentStatus         = 'Confirmed',
               ConfirmationTimestamp = SYSDATETIME(),
               ProviderReference     = @ProviderReference
        WHERE  PaymentID = @PaymentID;

        -- 2. SELECT Booking WITH (UPDLOCK) de lay thong tin
        DECLARE @BookingStatus VARCHAR(32);
        DECLARE @FinalAmount   DECIMAL(18,0);
        DECLARE @HoldExpiry    DATETIME2(7);
        DECLARE @ConcertID     INT;

        SELECT @BookingStatus = BookingStatus,
               @FinalAmount   = FinalAmount,
               @HoldExpiry    = HoldExpiryDatetime,
               @ConcertID     = ConcertID,
               @CustomerID    = CustomerUserID
        FROM   Booking WITH (UPDLOCK)
        WHERE  BookingID = @BookingID;

        IF @BookingStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52002, 'sp_ConfirmPayment: Booking khong ton tai.', 1;
        END

        -- 2b. Doi chieu so tien (DR-12/§12.20) - PHAI kiem TRUOC khi gianh quyen hieu luc.
        --
        -- Truoc day buoc nay nam o cuoi va xu ly bang ROLLBACK + THROW 52005. Do la mot
        -- lo mat tien co that, da tai hien duoc: khach bam "Thanh toan" (Payment sinh ra
        -- voi Amount = FinalAmount tai thoi diem do), sau do ap ma khuyen mai lam
        -- FinalAmount giam; cong thanh toan thu tien va bao thanh cong; SP nay ROLLBACK
        -- TOAN BO - ke ca buoc ghi PaymentStatus = 'Confirmed' o tren. Ket qua: tien da
        -- vao tai khoan thu nhung database khong he biet, khong phat hanh ve, va KHONG
        -- tao yeu cau hoan tien nao. Hold het han -> Booking Expired -> ghe nha ra ->
        -- khach mat trang.
        --
        -- Nguyen tac dung: mot khi cong thanh toan da bao thu tien, SU THAT TAI CHINH
        -- khong duoc phep bi vut bo. Neu don hang khong the thuc hien duoc thi phai
        -- HOAN TIEN, khong phai giả vờ giao dich chua tung xay ra. Day chinh la cach hai
        -- nhanh bat thuong con lai cua SP nay da lam (Payment trung - BR24b/LI02b;
        -- Booking het han - BR22a/LI02a); nhanh lech tien truoc day la ngoai le duy nhat,
        -- va do la mot thieu sot chu khong phai chu dich.
        --
        -- Dat TRUOC buoc 3 de khong phai gianh roi tra lai quyen hieu luc:
        -- IsBookingConfirmingPayment van la 0, nen Booking (dang con Pending) sau nay
        -- van co the duoc thanh toan lai bang dung so tien.
        IF @PaymentAmount <> @FinalAmount
        BEGIN
            DECLARE @Ref0 VARCHAR(64) = LOWER(CAST(NEWID() AS VARCHAR(36)));
            INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason, RefundConfirmationTimestamp, RefundReference)
            VALUES (@PaymentID, @PaymentAmount, 'Pending', SYSDATETIME(),
                    'Payment amount does not match booking total', NULL, @Ref0);

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@CustomerID, 'PAYMENT_AUTO_REFUNDED', 'Payment', CAST(@PaymentID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"Reason":"AmountMismatch","PaymentAmount":' + CAST(@PaymentAmount AS VARCHAR) +
                    ',"BookingFinalAmount":' + CAST(@FinalAmount AS VARCHAR) + '}');

            SET @Outcome = 'AutoRefunded_AmountMismatch';
            COMMIT TRANSACTION;
            RETURN;
        END

        -- 3. Thu UPDATE IsBookingConfirmingPayment = 1
        BEGIN TRY
            UPDATE Payment
            SET    IsBookingConfirmingPayment = 1
            WHERE  PaymentID = @PaymentID;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() = 2601 OR ERROR_NUMBER() = 2627 -- Vi pham Unique Index
            BEGIN
                -- Da co mot Payment khac xac nhan thanh cong cho Booking nay.
                -- Auto Refund 100% cho Payment hien tai (BR24b, LI02b)
                DECLARE @RefundID1 INT;
                DECLARE @Ref1 VARCHAR(64) = LOWER(CAST(NEWID() AS VARCHAR(36)));
                INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason, RefundConfirmationTimestamp, RefundReference)
                VALUES (@PaymentID, @PaymentAmount, 'Pending', SYSDATETIME(), 'Duplicate payment for booking', NULL, @Ref1);

                INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
                VALUES (@CustomerID, 'PAYMENT_AUTO_REFUNDED', 'Payment', CAST(@PaymentID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                        '{"Reason":"DuplicateEffectivePayment"}');

                SET @Outcome = 'AutoRefunded_DuplicatePayment';
                COMMIT TRANSACTION;
                RETURN;
            END
            ELSE
            BEGIN
                THROW;
            END
        END CATCH

        -- 4. Kiem tra Booking hieu luc (BR22)
        IF @BookingStatus <> 'Pending' OR @HoldExpiry <= SYSDATETIME()
        BEGIN
            -- Booking da Expired, Cancelled hoac Confirmed do race condition
            -- Giu nguyen Booking, auto Refund 100% cho Payment nay (BR22a, LI02a)
            DECLARE @RefundID2 INT;
            DECLARE @Ref2 VARCHAR(64) = LOWER(CAST(NEWID() AS VARCHAR(36)));
            INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason, RefundConfirmationTimestamp, RefundReference)
            VALUES (@PaymentID, @PaymentAmount, 'Pending', SYSDATETIME(), 'Booking expired or no longer pending', NULL, @Ref2);

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@CustomerID, 'PAYMENT_AUTO_REFUNDED', 'Payment', CAST(@PaymentID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"Reason":"BookingNoLongerPending","BookingStatus":"' + @BookingStatus + '"}');

            SET @Outcome = 'AutoRefunded_BookingNotPending';
            COMMIT TRANSACTION;
            RETURN;
        END

        -- 5. Phat hanh Ticket truoc khi Booking -> Confirmed de tranh vi pham trigger B3
        INSERT INTO Ticket
            (BookingID, EventSeatID, ConcertID, TicketCode, TicketStatus, IssuedTimestamp)
        SELECT @BookingID,
               besa.EventSeatID,
               @ConcertID,
               LOWER(CAST(NEWID() AS VARCHAR(36))),
               'Issued',
               SYSDATETIME()
        FROM   BookingEventSeatAllocation besa
        WHERE  besa.BookingID = @BookingID
          AND  besa.AllocationStatus = 'Active';

        -- Chuyen Booking -> Confirmed
        UPDATE Booking
        SET    BookingStatus      = 'Confirmed',
               ConfirmedTimestamp = SYSDATETIME()
        WHERE  BookingID = @BookingID;

        -- Cap nhat EventSeat -> Booked
        UPDATE EventSeat
        SET    InventoryStatus = 'Booked'
        WHERE  EventSeatID IN (
                   SELECT EventSeatID
                   FROM   BookingEventSeatAllocation
                   WHERE  BookingID = @BookingID
                     AND  AllocationStatus = 'Active'
               );

        -- Ghi AuditRecord (I-05: Them Audit cho Booking va Ticket)
        DECLARE @Now DATETIME2(7) = SYSDATETIME();
        DECLARE @TxnRef VARCHAR(64) = LOWER(CAST(NEWID() AS VARCHAR(36)));
        
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue, TransactionReference)
        VALUES (@CustomerID, 'PAYMENT_CONFIRMED', 'Payment', CAST(@PaymentID AS VARCHAR(64)), 'UPDATE', @Now,
                '{"PaymentStatus":"Confirmed"}', @TxnRef);
                
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue, TransactionReference)
        VALUES (@CustomerID, 'BOOKING_CONFIRMED', 'Booking', CAST(@BookingID AS VARCHAR(64)), 'UPDATE', @Now,
                '{"BookingStatus":"Confirmed"}', @TxnRef);
                
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue, TransactionReference)
        VALUES (@CustomerID, 'TICKETS_ISSUED', 'Booking', CAST(@BookingID AS VARCHAR(64)), 'INSERT', @Now,
                '{"Action":"Tickets Generated"}', @TxnRef);

        SET @Outcome = 'Confirmed';
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
