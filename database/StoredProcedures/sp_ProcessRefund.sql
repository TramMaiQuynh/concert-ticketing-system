-- ============================================================
-- sp_ProcessRefund (BP8 / BR31-BR34 / CT-06)
-- Xu ly hoan tien cho mot Payment da duoc Confirmed.
-- Transaction bao gom:
--   1. Kiem tra Payment o trang thai Confirmed.
--   2. Kiem tra tong Refund hien tai + so tien moi <= Payment.Amount.
--   3. INSERT Refund (trang thai Pending hoac Confirmed).
--   4. Ghi AuditRecord.
-- ============================================================
CREATE PROCEDURE dbo.sp_ProcessRefund
(
    @PaymentID       INT,
    @RefundAmount    DECIMAL(18,0),
    @RefundReason    NVARCHAR(500) = NULL,
    @ActorUserID     INT,
    @RefundReference VARCHAR(64)   = NULL,
    @NewRefundID     INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Kiem tra Payment ton tai va da Confirmed
        DECLARE @PaymentAmount  DECIMAL(18,0);
        DECLARE @PaymentStatus  VARCHAR(32);

        SELECT @PaymentAmount = Amount,
               @PaymentStatus = PaymentStatus
        FROM   Payment WITH (UPDLOCK)
        WHERE  PaymentID = @PaymentID;

        IF @PaymentAmount IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53001, 'sp_ProcessRefund: PaymentID khong ton tai.', 1;
        END

        IF @PaymentStatus NOT IN ('Confirmed')
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53002, 'sp_ProcessRefund: Chi duoc hoan tien cho Payment da Confirmed.', 1;
        END

        IF @RefundAmount <= 0
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53003, 'sp_ProcessRefund: RefundAmount phai lon hon 0.', 1;
        END

        -- 2. Kiem tra tong Refund khong vuot qua Payment.Amount (CT-06)
        DECLARE @TotalRefunded DECIMAL(18,0);
        SELECT  @TotalRefunded = ISNULL(SUM(RefundAmount), 0)
        FROM    Refund
        WHERE   PaymentID    = @PaymentID
          AND   RefundStatus NOT IN ('Failed', 'Cancelled');

        IF (@TotalRefunded + @RefundAmount) > @PaymentAmount
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53004, 'sp_ProcessRefund: Tong RefundAmount vuot qua Payment.Amount (CT-06).', 1;
        END

        -- 3. INSERT Refund
        INSERT INTO Refund
            (PaymentID, RefundStatus, RefundAmount, RefundReason,
             RefundRequestTimestamp, RefundReference)
        VALUES
            (@PaymentID, 'Pending', @RefundAmount, @RefundReason,
             SYSDATETIME(), @RefundReference);

        SET @NewRefundID = SCOPE_IDENTITY();

        -- 4. Ghi AuditRecord
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@ActorUserID, 'REFUND_REQUESTED', 'Refund',
             CAST(@NewRefundID AS VARCHAR(64)), 'INSERT',
             SYSDATETIME(),
             '{"RefundStatus":"Pending","RefundAmount":' + CAST(@RefundAmount AS VARCHAR) + '}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
