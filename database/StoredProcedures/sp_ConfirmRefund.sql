-- ============================================================
-- sp_ConfirmRefund (BP8 / BR32 / §10.1 state machine)
-- Hoan tat hoan tien: Refund Pending -> Confirmed.
-- Neu tong Refund Confirmed dat 100% Payment.Amount -> Payment -> Refunded.
--
-- Ly thuyet (state machine §10.1):
--   Refund: Pending -> Confirmed (terminal)
--   Payment: Confirmed -> Refunded (terminal)
-- Day la buoc thu 2 sau sp_ProcessRefund (request -> Pending).
-- Thuc te thanh toan: buoc confirm thuong tuong tac voi payment
-- gateway ben ngoai; SP nay dai dien buoc settlement/confirmation.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfirmRefund
(
    @RefundID   INT,
    @ActorUserID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Refund phai ton tai va dang Pending
        DECLARE @PaymentID INT, @RefundAmount DECIMAL(18,0), @RefundStatus VARCHAR(32);
        SELECT @PaymentID = PaymentID, @RefundAmount = RefundAmount, @RefundStatus = RefundStatus
        FROM   Refund
        WHERE  RefundID = @RefundID;

        IF @PaymentID IS NULL
            THROW 53101, 'sp_ConfirmRefund: Refund khong ton tai.', 1;

        IF @RefundStatus <> 'Pending'
            THROW 53102, 'sp_ConfirmRefund: Chi confirm Refund dang Pending.', 1;

        -- 2. Quyen: Admin hoac Organizer cua Concert cua Booking chua Payment
        DECLARE @ConcertOrg INT;
        SELECT @ConcertOrg = c.OrganizerUserID
        FROM   Payment p
        JOIN   Booking b ON b.BookingID = p.BookingID
        JOIN   Concert c ON c.ConcertID = b.ConcertID
        WHERE  p.PaymentID = @PaymentID;

        IF NOT (
            @ActorUserID = @ConcertOrg
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 53103, 'sp_ConfirmRefund: Actor khong co quyen.', 1;

        -- 3. Chuyen Refund -> Confirmed
        UPDATE Refund
        SET    RefundStatus = 'Confirmed',
               RefundConfirmationTimestamp = SYSDATETIME()
        WHERE  RefundID = @RefundID;

        -- 4. Neu tong Refund Confirmed dat 100% Payment.Amount -> Payment -> Refunded
        DECLARE @PaymentAmount DECIMAL(18,0);
        SELECT @PaymentAmount = Amount FROM Payment WHERE PaymentID = @PaymentID;

        DECLARE @TotalConfirmed DECIMAL(18,0);
        SELECT @TotalConfirmed = ISNULL(SUM(RefundAmount), 0)
        FROM   Refund
        WHERE  PaymentID = @PaymentID AND RefundStatus = 'Confirmed';

        IF @TotalConfirmed >= @PaymentAmount
        BEGIN
            UPDATE Payment
            SET    PaymentStatus = 'Refunded'
            WHERE  PaymentID = @PaymentID AND PaymentStatus = 'Confirmed';
        END

        -- 5. Audit
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'REFUND_CONFIRMED', 'Refund',
                CAST(@RefundID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"RefundStatus":"Confirmed","PaymentID":' + CAST(@PaymentID AS VARCHAR) +
                CASE WHEN @TotalConfirmed >= @PaymentAmount THEN ',"PaymentStatus":"Refunded"' ELSE '' END + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO