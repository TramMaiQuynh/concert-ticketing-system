-- ============================================================
-- sp_InitiatePayment 
-- Tao giao dich Payment cho Booking (trang thai Pending).
-- ============================================================
CREATE PROCEDURE dbo.sp_InitiatePayment
(
    @BookingID        INT,
    @CustomerUserID   INT,
    @NewPaymentID     INT           OUTPUT,
    @PaymentReference VARCHAR(64)   OUTPUT,
    @Amount           DECIMAL(18,0) OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Kiem tra Booking hop le
        DECLARE @BookingStatus VARCHAR(32);
        
        SELECT @BookingStatus = BookingStatus,
               @Amount        = FinalAmount
        FROM   Booking WITH (UPDLOCK)
        WHERE  BookingID = @BookingID
          AND  CustomerUserID = @CustomerUserID;

        IF @BookingStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 56001, 'sp_InitiatePayment: Booking khong ton tai hoac khong thuoc ve ban.', 1;
        END

        IF @BookingStatus <> 'Pending'
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 56002, 'sp_InitiatePayment: Chi co the thanh toan cho Booking Pending.', 1;
        END

        -- 2. Kiem tra chua co Payment Pending nao
        IF EXISTS (SELECT 1 FROM Payment WHERE BookingID = @BookingID AND PaymentStatus = 'Pending')
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 56003, 'sp_InitiatePayment: Đã có giao dịch thanh toán đang chờ xử lý cho Booking này.', 1;
        END

        -- 3. Sinh PaymentReference duy nhat
        -- Su dung NEWID() va bo dau '-' de lam Reference
        SET @PaymentReference = 'PAY-' + UPPER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', ''));

        -- 4. Tao Payment
        INSERT INTO Payment 
            (BookingID, PaymentStatus, Amount, Currency, PaymentReference, PaymentRequestTimestamp)
        VALUES 
            (@BookingID, 'Pending', @Amount, 'VND', @PaymentReference, SYSDATETIME());

        SET @NewPaymentID = SCOPE_IDENTITY();

        -- 5. Ghi AuditRecord
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@CustomerUserID, 'PAYMENT_INITIATED', 'Payment',
             CAST(@NewPaymentID AS VARCHAR(64)), 'INSERT',
             SYSDATETIME(),
             '{"PaymentStatus":"Pending","Amount":' + CAST(@Amount AS VARCHAR) + '}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
