-- ============================================================
-- sp_ConfirmPayment (BP6 / BR22-BR27 / FR24-FR30)
-- Thuat toan 5 buoc xu ly thanh toan + Race condition handling:
--   1. UPDATE Payment -> Confirmed vo dieu kien (ghi nhan su that tai chinh).
--   2. SELECT Booking voi UPDLOCK, HOLDLOCK de tuan tu hoa.
--   3. Thu xac lap IsBookingConfirmingPayment=1; neu vi pham UIX -> auto Refund.
--   4. Kiem tra Booking Pending & con han (HoldExpiry); neu het han -> auto Refund.
--   5. Phat hanh Ticket, chuyen Booking -> Confirmed, EventSeat -> Booked.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfirmPayment
(
    @BookingID         INT,
    @PaymentID         INT,
    @ProviderReference VARCHAR(64) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

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

        SELECT @PaymentAmount = Amount,
               @PaymentStatus = PaymentStatus
        FROM   Payment WITH (UPDLOCK)
        WHERE  PaymentID = @PaymentID AND BookingID = @BookingID;

        IF @PaymentAmount IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52001, 'sp_ConfirmPayment: Payment khong ton tai hoac khong thuoc Booking nay.', 1;
        END

        -- CRIT-10: Idempotency check
        IF @PaymentStatus = 'Confirmed'
        BEGIN
            COMMIT TRANSACTION;
            RETURN; -- Thanh cong, khong lam gi them (Idempotent)
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
                INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason, RefundConfirmationTimestamp)
                VALUES (@PaymentID, @PaymentAmount, 'Confirmed', SYSDATETIME(), 'Duplicate payment for booking', SYSDATETIME());
                
                UPDATE Payment SET PaymentStatus = 'Refunded' WHERE PaymentID = @PaymentID;
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
            INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason, RefundConfirmationTimestamp)
            VALUES (@PaymentID, @PaymentAmount, 'Confirmed', SYSDATETIME(), 'Booking expired or no longer pending', SYSDATETIME());
            
            UPDATE Payment SET PaymentStatus = 'Refunded' WHERE PaymentID = @PaymentID;
            COMMIT TRANSACTION;
            RETURN;
        END

        -- 5. Doi chieu Amount va xac nhan Booking
        IF @PaymentAmount <> @FinalAmount
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52005, 'sp_ConfirmPayment: Payment.Amount khong khop voi Booking.FinalAmount.', 1;
        END

        -- Chuyen Booking -> Confirmed
        UPDATE Booking
        SET    BookingStatus      = 'Confirmed',
               ConfirmedTimestamp = SYSDATETIME()
        WHERE  BookingID = @BookingID;

        -- Phat hanh Ticket
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
        
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@CustomerID, 'PAYMENT_CONFIRMED', 'Payment', CAST(@PaymentID AS VARCHAR(64)), 'UPDATE', @Now,
                '{"PaymentStatus":"Confirmed"}');
                
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@CustomerID, 'BOOKING_CONFIRMED', 'Booking', CAST(@BookingID AS VARCHAR(64)), 'UPDATE', @Now,
                '{"BookingStatus":"Confirmed"}');
                
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@CustomerID, 'TICKETS_ISSUED', 'Booking', CAST(@BookingID AS VARCHAR(64)), 'INSERT', @Now,
                '{"Action":"Tickets Generated"}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
