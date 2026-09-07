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
    @RefundReason          NVARCHAR(500) = NULL,
    @IsConcertCancellation BIT = 0,  -- BR34a: Override 100% Refund, bo qua deadline
    -- ID cua Refund vua tao, hoac NULL neu lan goi nay KHONG tao Refund nao
    -- (Booking dang Pending thi huy thang, khong co tien de hoan; hoac ty le hoan
    -- theo chinh sach Concert bang 0). Caller PHAI biet dieu do: truoc day backend
    -- doan RefundID bang cach lay dong moi nhat cua Booking, nen khi lan goi nay
    -- khong tao Refund thi no tra ve ID cua mot Refund CU khong lien quan - va co
    -- the dem chinh ID do di goi sp_ConfirmRefund.
    @NewRefundID           INT = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @NewRefundID = NULL;

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

        -- 2. Kiem tra quyen: chinh chu Booking, Organizer so huu Concert, hoac Admin.
        -- Chu Booking duoc tu huy (BR18a cho Pending, BR31 cho Confirmed) — day la
        -- quyen cua khach hang, khong phai dac quyen quan tri. Moi rang buoc chinh sach
        -- (han huy CI10, ty le hoan BR32a) van do SP tu ap dung ben duoi, nen viec
        -- mo quyen nay KHONG cho phep khach vuot qua chinh sach.
        -- Truong hop @IsConcertCancellation = 1 (BR34a) chi danh cho Organizer/Admin.
        DECLARE @OrganizerUserID INT;
        SELECT @OrganizerUserID = OrganizerUserID FROM Concert WHERE ConcertID = @ConcertID;

        DECLARE @IsPrivileged BIT =
            CASE WHEN @ActorUserID = @OrganizerUserID
                   OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                              JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                              WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin'
                                AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
                 THEN 1 ELSE 0 END;

        IF @IsPrivileged = 0 AND @ActorUserID <> @CustomerID
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53011, 'sp_ProcessRefund: Actor khong co quyen.', 1;
        END

        IF @IsConcertCancellation = 1 AND @IsPrivileged = 0
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 53016, 'sp_ProcessRefund: Chi Organizer/Admin duoc huy theo dien huy Concert (BR34a).', 1;
        END



        -- ====================================================
        -- Nhanh 1: Booking dang Pending (BR18a)
        -- ====================================================
        IF @BookingStatus = 'Pending'
        BEGIN
            -- Chuyen Booking -> Cancelled (kem dau thoi gian, CHK_Booking_TimestampCoherence)
            UPDATE Booking
            SET    BookingStatus = 'Cancelled',
                   CancelledTimestamp = SYSDATETIME()
            WHERE  BookingID = @BookingID;

            -- Giai phong Allocation
            UPDATE BookingEventSeatAllocation
            SET    AllocationStatus = 'Released', ReleaseTimestamp = SYSDATETIME()
            WHERE  BookingID = @BookingID AND AllocationStatus = 'Active';

            -- Giai phong EventSeat
            UPDATE es
            SET    InventoryStatus = CASE 
                                     WHEN EXISTS (
                                         SELECT 1 FROM Waitlist w 
                                         JOIN WaitlistEntry we ON w.WaitlistID = we.WaitlistID 
                                         WHERE w.ConcertID = es.ConcertID 
                                           AND w.WaitlistStatus = 'Open' 
                                           AND we.TicketCategoryID = es.TicketCategoryID 
                                           AND we.EntryStatus = 'Active'
                                     )
                                     THEN 'OnHoldForWaitlist' 
                                     ELSE 'Available' 
                                     END
            FROM   EventSeat es
            WHERE  es.EventSeatID IN (SELECT EventSeatID FROM BookingEventSeatAllocation WHERE BookingID = @BookingID)
              AND  es.InventoryStatus IN ('OnHold', 'Booked');

            -- Audit
            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'BOOKING_CANCELLED', 'Booking', CAST(@BookingID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"BookingStatus":"Cancelled","Reason":"' + STRING_ESCAPE(ISNULL(@RefundReason, 'Pending Booking Cancelled'), 'json') + '"}');

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
                    -- CI10: chi cho huy khi NOW() < deadline. Bien bi LOAI TRU tai dung
                    -- moc deadline, nen phai la >= (truoc day dung > nen dung moc deadline
                    -- van huy duoc - lech mot don vi thoi gian so voi chinh sach cong bo).
                    IF SYSDATETIME() >= @Deadline
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

            IF @FinalRefundAmount > @PaymentAmount
                SET @FinalRefundAmount = @PaymentAmount;

            -- c. Chuyen Booking -> Cancelled (kem dau thoi gian)
            UPDATE Booking
            SET    BookingStatus = 'Cancelled',
                   CancelledTimestamp = SYSDATETIME()
            WHERE  BookingID = @BookingID;

            -- d. Chuyen toan bo Ticket -> Cancelled (kem dau thoi gian)
            UPDATE Ticket
            SET    TicketStatus = 'Cancelled',
                   CancelledTimestamp = SYSDATETIME()
            WHERE  BookingID = @BookingID AND TicketStatus = 'Issued';

            -- e. Giai phong Allocation
            UPDATE BookingEventSeatAllocation
            SET    AllocationStatus = 'Released', ReleaseTimestamp = SYSDATETIME()
            WHERE  BookingID = @BookingID AND AllocationStatus = 'Active';

            -- f. Giai phong EventSeat
            UPDATE es
            SET    InventoryStatus = CASE 
                                     WHEN EXISTS (
                                         SELECT 1 FROM Waitlist w 
                                         JOIN WaitlistEntry we ON w.WaitlistID = we.WaitlistID 
                                         WHERE w.ConcertID = es.ConcertID 
                                           AND w.WaitlistStatus = 'Open' 
                                           AND we.TicketCategoryID = es.TicketCategoryID 
                                           AND we.EntryStatus = 'Active'
                                     )
                                     THEN 'OnHoldForWaitlist' 
                                     ELSE 'Available' 
                                     END
            FROM   EventSeat es
            WHERE  es.EventSeatID IN (SELECT EventSeatID FROM BookingEventSeatAllocation WHERE BookingID = @BookingID)
              AND  es.InventoryStatus IN ('OnHold', 'Booked');

            -- g. Tao Refund o trang thai Pending (cho process thanh toan)
            IF @FinalRefundAmount > 0
            BEGIN
                DECLARE @Ref VARCHAR(64) = LOWER(CAST(NEWID() AS VARCHAR(36)));
                INSERT INTO Refund (PaymentID, RefundAmount, RefundStatus, RefundRequestTimestamp, RefundReason, RefundReference)
                VALUES (@PaymentID, @FinalRefundAmount, 'Pending', SYSDATETIME(), @RefundReason, @Ref);

                SET @NewRefundID = SCOPE_IDENTITY();

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
