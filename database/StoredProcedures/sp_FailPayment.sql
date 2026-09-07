-- ============================================================
-- sp_FailPayment (B-01)
-- Ghi nhan trang thai thanh toan that bai tu cong thanh toan.
-- Thuc thi atomic conditional update de dam bao idempotency voi webhook.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_FailPayment
    @PaymentID INT, 
    @ProviderReference VARCHAR(64) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        BEGIN TRANSACTION;

        UPDATE Payment
        SET    PaymentStatus     = 'Failed',
               FailureTimestamp  = SYSDATETIME(),
               ProviderReference = @ProviderReference
        WHERE  PaymentID = @PaymentID
          AND  PaymentStatus = 'Pending';   -- BR49a: Atomic Conditional Update

        IF @@ROWCOUNT = 1
        BEGIN
            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType,
                                     EntityID, Action, EventTimestamp, NewValue)
            SELECT b.CustomerUserID, 'PAYMENT_FAILED', 'Payment',
                   CAST(@PaymentID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                   '{"PaymentStatus":"Failed"}'
            FROM Payment p JOIN Booking b ON b.BookingID = p.BookingID
            WHERE p.PaymentID = @PaymentID;
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
