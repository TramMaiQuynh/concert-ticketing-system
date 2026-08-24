-- ============================================================
-- sp_ConfirmPayment (BP6 / BR22-BR27 / FR24-FR30)
-- Xac nhan Payment va phat hanh Ticket sau khi thanh toan thanh cong.
-- Transaction bao gom:
--   1. Kiem tra Booking con hieu luc (Pending) va Payment hop le.
--   2. Payment.Amount = Booking.FinalAmount.
--   3. Chuyen Payment -> Confirmed.
--   4. Chuyen Booking -> Confirmed.
--   5. Phat hanh Ticket cho moi Active Allocation.
--   6. Chuyen EventSeat -> Booked.
--   7. Ghi AuditRecord.
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

        -- --------------------------------------------------------
        -- 1. Lay thong tin Booking
        -- --------------------------------------------------------
        DECLARE @BookingStatus  VARCHAR(32);
        DECLARE @FinalAmount    DECIMAL(18,0);
        DECLARE @ConcertID      INT;
        DECLARE @CustomerID     INT;

        SELECT @BookingStatus = BookingStatus,
               @FinalAmount   = FinalAmount,
               @ConcertID     = ConcertID,
               @CustomerID    = CustomerUserID
        FROM   Booking WITH (UPDLOCK)
        WHERE  BookingID = @BookingID;

        IF @BookingStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52001, 'sp_ConfirmPayment: BookingID khong ton tai.', 1;
        END

        IF @BookingStatus <> 'Pending'
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52002, 'sp_ConfirmPayment: Booking khong o trang thai Pending, khong the xac nhan Payment.', 1;
        END

        -- --------------------------------------------------------
        -- 2. Kiem tra Payment ton tai va chua duoc Confirmed
        -- --------------------------------------------------------
        DECLARE @PaymentAmount  DECIMAL(18,0);
        DECLARE @PaymentStatus  VARCHAR(32);

        SELECT @PaymentAmount = Amount,
               @PaymentStatus = PaymentStatus
        FROM   Payment WITH (UPDLOCK)
        WHERE  PaymentID  = @PaymentID
          AND  BookingID  = @BookingID;

        IF @PaymentAmount IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52003, 'sp_ConfirmPayment: PaymentID khong ton tai hoac khong thuoc Booking nay.', 1;
        END

        IF @PaymentStatus <> 'Pending'
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52004, 'sp_ConfirmPayment: Payment khong o trang thai Pending.', 1;
        END

        -- --------------------------------------------------------
        -- 3. Kiem tra Payment.Amount = Booking.FinalAmount (DR-12)
        -- --------------------------------------------------------
        IF @PaymentAmount <> @FinalAmount
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 52005, 'sp_ConfirmPayment: Payment.Amount khong khop voi Booking.FinalAmount.', 1;
        END

        -- --------------------------------------------------------
        -- 4. Chuyen Payment -> Confirmed
        -- --------------------------------------------------------
        UPDATE Payment
        SET    PaymentStatus          = 'Confirmed',
               ConfirmationTimestamp  = SYSDATETIME(),
               ProviderReference      = @ProviderReference
        WHERE  PaymentID = @PaymentID;

        -- --------------------------------------------------------
        -- 5. Chuyen Booking -> Confirmed
        -- --------------------------------------------------------
        UPDATE Booking
        SET    BookingStatus         = 'Confirmed',
               ConfirmedTimestamp    = SYSDATETIME()
        WHERE  BookingID = @BookingID;

        -- --------------------------------------------------------
        -- 6. Phat hanh Ticket cho moi Active Allocation (B3)
        --    Moi Allocation nhan 1 Ticket voi TicketCode = NEWID()
        -- --------------------------------------------------------
        INSERT INTO Ticket
            (BookingID, EventSeatID, ConcertID, TicketCode,
             TicketStatus, IssuedTimestamp)
        SELECT @BookingID,
               besa.EventSeatID,
               @ConcertID,
               UPPER(REPLACE(CAST(NEWID() AS VARCHAR(36)), '-', '')),  -- 32 ky tu unique
               'Issued',
               SYSDATETIME()
        FROM   BookingEventSeatAllocation besa
        WHERE  besa.BookingID        = @BookingID
          AND  besa.AllocationStatus = 'Active';

        -- --------------------------------------------------------
        -- 7. Chuyen EventSeat -> Booked
        -- --------------------------------------------------------
        UPDATE EventSeat
        SET    InventoryStatus = 'Booked'
        WHERE  EventSeatID IN (
                   SELECT EventSeatID
                   FROM   BookingEventSeatAllocation
                   WHERE  BookingID        = @BookingID
                     AND  AllocationStatus = 'Active'
               );

        -- --------------------------------------------------------
        -- 8. Ghi AuditRecord
        -- --------------------------------------------------------
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@CustomerID, 'PAYMENT_CONFIRMED', 'Payment',
             CAST(@PaymentID AS VARCHAR(64)), 'UPDATE',
             SYSDATETIME(),
             '{"PaymentStatus":"Confirmed","BookingStatus":"Confirmed"}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
