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

        -- Idempotent voi webhook settlement gui lap (BR49a) - dong bo voi
        -- sp_ConfirmPayment va sp_FailPayment. Mot lan goi lai cho khoan hoan DA
        -- settle khong phai la loi: cong thanh toan gui lai callback la chuyen
        -- binh thuong, va tra ve loi o day chi lam cong gui lai nhieu hon nua.
        IF @RefundStatus = 'Confirmed'
        BEGIN
            COMMIT TRANSACTION;
            RETURN;
        END

        -- Failed/Cancelled thi khac han: khoan hoan da bi bo, khong duoc settle nua.
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
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 53103, 'sp_ConfirmRefund: Actor khong co quyen.', 1;

        -- 3. Chuyen Refund -> Confirmed bang atomic conditional update (BR49a).
        --    Dieu kien `AND RefundStatus = 'Pending'` la lop chan that su chong
        --    webhook/thao tac lap: kiem tra o buoc 1 va lenh UPDATE la hai thoi diem
        --    khac nhau, khong co dieu kien nay thi hai luong dong thoi deu di qua
        --    va deu cong don vao @TotalConfirmed o buoc 4.
        UPDATE Refund
        SET    RefundStatus = 'Confirmed',
               RefundConfirmationTimestamp = SYSDATETIME()
        WHERE  RefundID = @RefundID
          AND  RefundStatus = 'Pending';

        IF @@ROWCOUNT = 0
        BEGIN
            -- Luong khac vua confirm truoc: coi nhu da hoan tat (idempotent).
            COMMIT TRANSACTION;
            RETURN;
        END

        -- 4. Neu tong Refund Confirmed dat 100% Payment.Amount -> Payment -> Refunded
        DECLARE @PaymentAmount DECIMAL(18,0);
        SELECT @PaymentAmount = Amount FROM Payment WHERE PaymentID = @PaymentID;

        DECLARE @TotalConfirmed DECIMAL(18,0);
        SELECT @TotalConfirmed = ISNULL(SUM(RefundAmount), 0)
        FROM   Refund
        WHERE  PaymentID = @PaymentID AND RefundStatus = 'Confirmed';

        IF @TotalConfirmed > 0
        BEGIN
            DECLARE @NewStatus VARCHAR(32) = CASE WHEN @TotalConfirmed >= @PaymentAmount THEN 'Refunded' ELSE 'PartiallyRefunded' END;
            
            UPDATE Payment
            SET    PaymentStatus = @NewStatus
            WHERE  PaymentID = @PaymentID AND PaymentStatus IN ('Confirmed', 'PartiallyRefunded');
        END

        -- 5. Audit
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'REFUND_CONFIRMED', 'Refund',
                CAST(@RefundID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"RefundStatus":"Confirmed","PaymentID":' + CAST(@PaymentID AS VARCHAR) +
                CASE WHEN @TotalConfirmed > 0 THEN ',"PaymentStatus":"' + (CASE WHEN @TotalConfirmed >= @PaymentAmount THEN 'Refunded' ELSE 'PartiallyRefunded' END) + '"' ELSE '' END + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO