-- ============================================================
-- sp_ProcessRefund (BP8 / BR18a, BR31-BR34a)
-- Diem vao duy nhat de huy Booking (Pending/Confirmed).
-- Neu Pending: huy truc tiep, khong tao hoan tien.
-- Neu Confirmed: huy Booking, huy Ticket, giai phong ghe, va thuc hien
-- hoan tien (tao + confirm Refund ngay lap tuc theo spec).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ProcessRefund
(
    @BookingID             INT,
    @ActorUserID           INT,
    @RequestedRefundAmount DECIMAL(18,0) = NULL,
    @RefundReason          NVARCHAR(500) = NULL,
    @IsConcertCancellation BIT = 0  -- BR34a: Override 100% Refund, bo qua deadline
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Lay thong tin Booking, Payment, Concert
        DECLARE @BookingStatus VARCHAR(32);
        DECLARE @CustomerID INT;
        DECLARE @ConcertID INT;
        DECLARE @StartDatetime DATETIME2(7);
        DECLARE @CancellationDeadlineHours INT;
        DECLARE @RefundPercentage DECIMAL(5,2);

        SELECT @BookingStatus = b.BookingStatus,
               @CustomerID    = b.CustomerUserID,
               @ConcertID     = b.ConcertID,
               @StartDatetime = c.StartDatetime,
               @CancellationDeadlineHours = c.CancellationDeadlineHours,
               @RefundPercentage  = c.RefundPercentage
        FROM   Booking b WITH (UPDLOCK)
        JOIN   Concert c ON c.ConcertID = b.ConcertID
        WHERE  b.BookingID = @BookingID;

        IF @BookingStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53010, 'sp_ProcessRefund: Booking khong ton tai.', 1;
        END

        -- 2. Kiem tra quyen (Admin hoac Organizer)
        DECLARE @OrganizerUserID INT;
        SELECT @OrganizerUserID = OrganizerUserID FROM Concert WHERE ConcertID = @ConcertID;
        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53011, 'sp_ProcessRefund: Actor khong co quyen.', 1;
        END

        -- Kiem tra Waitlist Active de ap dung BR33a (OnHoldForWaitlist)
        DECLARE @HasActiveWaitlist BIT = 0;
        IF EXISTS (SELECT 1 FROM Waitlist w JOIN WaitlistEntry we ON we.WaitlistID = w.WaitlistID
                   WHERE w.ConcertID = @ConcertID AND we.EntryStatus = 'Active')
            SET @HasActiveWaitlist = 1;

        DECLARE @TargetInventoryStatus VARCHAR(32) = CASE WHEN @HasActiveWaitlist = 1 THEN 'OnHoldForWaitlist' ELSE 'Available' END;

        -- ====================================================
        -- Nhanh 1: Booking dang Pending (BR18a)
        -- ====================================================
        IF @BookingStatus = 'Pending'
        BEGIN
            -- Chuyen Booking -> Cancelled
            UPDATE Booking SET BookingStatus = 'Cancelled' WHERE BookingID = @BookingID;

            -- Giai phong EventSeat
            UPDATE EventSeat
            SET    InventoryStatus = @TargetInventoryStatus
            WHERE  EventSeatID IN (SELECT EventSeatID FROM BookingEventSeatAllocation WHERE BookingID = @BookingID);

            -- Giai phong Allocation
            UPDATE BookingEventSeatAllocation
            SET    AllocationStatus = 'Released', ReleaseTimestamp = SYSDATETIME()
            WHERE  BookingID = @BookingID AND AllocationStatus = 'Active';

            -- Audit
            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'BOOKING_CANCELLED', 'Booking', CAST(@BookingID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"BookingStatus":"Cancelled","Reason":"' + ISNULL(@RefundReason, 'Pending Booking Cancelled') + '"}');

            COMMIT TRANSACTION;
            RETURN;
        END

        -- ====================================================
        -- Nhanh 2: Booking dang Confirmed
        -- ====================================================
        IF @BookingStatus = 'Confirmed'
        BEGIN
            -- Lay Payment Confirming
            DECLARE @PaymentID INT, @PaymentAmount DECIMAL(18,0);
            SELECT @PaymentID = PaymentID, @PaymentAmount = Amount
            FROM   Payment
            WHERE  BookingID = @BookingID AND IsBookingConfirmingPayment = 1 AND PaymentStatus = 'Confirmed';

            IF @PaymentID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 53012, 'sp_ProcessRefund: Khong tim thay Payment hop le cua Booking Confirmed nay.', 1;
            END

            -- a. Kiem tra han huy (CI10)
            IF @IsConcertCancellation = 0
            BEGIN
                IF @CancellationDeadlineHours IS NOT NULL
                BEGIN
                    DECLARE @Deadline DATETIME2(7) = DATEADD(HOUR, -@CancellationDeadlineHours, @StartDatetime);
                    IF SYSDATETIME() > @Deadline
                    BEGIN
                        ROLLBACK TRANSACTION;
                        THROW 53013, 'sp_ProcessRefund: Da qua han huy ve hoac dang trong thoi gian cam huy.', 1;
                    END
                END
                ELSE
                BEGIN
                    -- Neu NULL tuc la khong cho phep huy
                    ROLLBACK TRANSACTION;
                    THROW 53013, 'sp_ProcessRefund: Concert khong cho phep huy ve.', 1;
                END
            END

            -- b. Tinh gia tri hoan
            DECLARE @FinalRefundAmount DECIMAL(18,0) = 0;
            IF @IsConcertCancellation = 1
                SET @FinalRefundAmount = @PaymentAmount; -- Override 100%
            ELSE
            BEGIN
                IF @RefundPercentage IS NOT NULL
                    SET @FinalRefundAmount = CAST(@PaymentAmount * @RefundPercentage / 100.0 AS DECIMAL(18,0));
                ELSE
                    SET @FinalRefundAmount = 0;
            END

            -- d. Chuyen toan bo Ticket -> Cancelled

            IF @FinalRefundAmount > @PaymentAmount
                SET @FinalRefundAmount = @PaymentAmount;

            -- c. Chuyen Booking -> Cancelled
            UPDATE Booking SET BookingStatus = 'Cancelled' WHERE BookingID = @BookingID;

            -- d. Chuyen toan bo Ticket -> Cancelled
            UPDATE Ticket SET TicketStatus = 'Cancelled' WHERE BookingID = @BookingID AND TicketStatus = 'Issued';

            -- e. Giai phong EventSeat
            UPDATE EventSeat
            SET    InventoryStatus = @TargetInventoryStatus
            WHERE  EventSeatID IN (SELECT EventSeatID FROM BookingEventSeatAllocation WHERE BookingID = @BookingID);

            -- f. Giai phong Allocation
            UPDATE BookingEventSeatAllocation
            SET    AllocationStatus = 'Released', ReleaseTimestamp = SYSDATETIME()
            WHERE  BookingID = @BookingID AND AllocationStatus = 'Active';

            -- g. Tao Refund o trang thai Pending (cho process thanh toan)
            IF @FinalRefundAmount > 0
            BEGIN
                INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason)
                VALUES (@PaymentID, @FinalRefundAmount, 'Pending', SYSDATETIME(), @RefundReason);

                -- Khong xac nhan PaymentStatus thanh Refunded ngay vi refund moi dang Pending
            END

            -- h. Audit
            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'BOOKING_CANCELLED_WITH_REFUND', 'Booking', CAST(@BookingID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"BookingStatus":"Cancelled","RefundAmount":' + CAST(@FinalRefundAmount AS VARCHAR) + '}');

            COMMIT TRANSACTION;
            RETURN;
        END

        -- Cac trang thai khac (Cancelled, Expired) khong duoc phep refund
        ROLLBACK TRANSACTION;
        THROW 53015, 'sp_ProcessRefund: Booking khong the huy (khong phai Pending/Confirmed).', 1;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
