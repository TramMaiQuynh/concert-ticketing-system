-- ============================================================
-- TRG_StateTransition
-- Kiem tra moi chuyen doi trang thai (OLD -> NEW) hop le
-- theo state machine duoc dinh nghia tai §10.1 (BR49).
-- Ap dung cho: Concert, EventSeat, Booking, Payment,
--              Ticket, Refund, Waitlist, WaitlistEntry,
--              Queue, QueueEntry.
-- ============================================================

-- --- Concert ---
CREATE OR ALTER TRIGGER TRG_Concert_StateTransition
ON Concert
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(ConcertStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.ConcertID = i.ConcertID
        WHERE  -- Valid transitions: Draft->Published, Published->OnSale|Cancelled,
               --   OnSale->SaleClosed|Cancelled, SaleClosed->Completed|Cancelled
               NOT (
                   (d.ConcertStatus = 'Draft'       AND i.ConcertStatus IN ('Published'))
                OR (d.ConcertStatus = 'Published'   AND i.ConcertStatus IN ('OnSale', 'Cancelled'))
                OR (d.ConcertStatus = 'OnSale'      AND i.ConcertStatus IN ('SaleClosed', 'Cancelled'))
                OR (d.ConcertStatus = 'SaleClosed'  AND i.ConcertStatus IN ('Completed', 'Cancelled'))
                OR (d.ConcertStatus = i.ConcertStatus) -- no-op update allowed
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50001, 'BR49 Violation: Chuyen doi trang thai Concert khong hop le.', 1;
    END
END;
GO

-- --- Booking ---
CREATE OR ALTER TRIGGER TRG_Booking_StateTransition
ON Booking
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(BookingStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.BookingID = i.BookingID
        WHERE  NOT (
                   (d.BookingStatus = 'Pending'   AND i.BookingStatus IN ('Confirmed', 'Expired', 'Cancelled'))
                OR (d.BookingStatus = 'Confirmed' AND i.BookingStatus IN ('Cancelled'))
                OR (d.BookingStatus = i.BookingStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50002, 'BR49 Violation: Chuyen doi trang thai Booking khong hop le.', 1;
    END
END;
GO

-- --- Payment ---
CREATE OR ALTER TRIGGER TRG_Payment_StateTransition
ON Payment
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(PaymentStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.PaymentID = i.PaymentID
        WHERE  NOT (
                   (d.PaymentStatus = 'Pending'   AND i.PaymentStatus IN ('Confirmed', 'Failed'))
                OR (d.PaymentStatus = 'Confirmed' AND i.PaymentStatus IN ('Refunded'))
                OR (d.PaymentStatus = i.PaymentStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50003, 'BR49 Violation: Chuyen doi trang thai Payment khong hop le.', 1;
    END
END;
GO

-- --- Ticket ---
CREATE OR ALTER TRIGGER TRG_Ticket_StateTransition
ON Ticket
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(TicketStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.TicketID = i.TicketID
        WHERE  NOT (
                   (d.TicketStatus = 'Issued' AND i.TicketStatus IN ('Used', 'Cancelled'))
                OR (d.TicketStatus = i.TicketStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50004, 'BR49 Violation: Chuyen doi trang thai Ticket khong hop le.', 1;
    END
END;
GO

-- --- EventSeat ---
CREATE OR ALTER TRIGGER TRG_EventSeat_StateTransition
ON EventSeat
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(InventoryStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.EventSeatID = i.EventSeatID
        WHERE  NOT (
                   (d.InventoryStatus = 'Available'         AND i.InventoryStatus IN ('OnHold', 'OnHoldForWaitlist', 'Unavailable'))
                OR (d.InventoryStatus = 'OnHold'            AND i.InventoryStatus IN ('Available', 'Booked'))
                OR (d.InventoryStatus = 'OnHoldForWaitlist' AND i.InventoryStatus IN ('Available', 'OnHold'))
                OR (d.InventoryStatus = 'Booked'            AND i.InventoryStatus IN ('Available'))
                OR (d.InventoryStatus = i.InventoryStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50005, 'BR49 Violation: Chuyen doi trang thai EventSeat khong hop le.', 1;
    END
END;
GO

-- --- Refund ---
CREATE OR ALTER TRIGGER TRG_Refund_StateTransition
ON Refund
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(RefundStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.RefundID = i.RefundID
        WHERE  NOT (
                   (d.RefundStatus = 'Pending' AND i.RefundStatus IN ('Confirmed', 'Failed', 'Cancelled'))
                OR (d.RefundStatus = i.RefundStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50006, 'BR49 Violation: Chuyen doi trang thai Refund khong hop le.', 1;
    END
END;
GO

-- --- WaitlistEntry ---
CREATE OR ALTER TRIGGER TRG_WaitlistEntry_StateTransition
ON WaitlistEntry
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(EntryStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.WaitlistEntryID = i.WaitlistEntryID
        WHERE  NOT (
                   (d.EntryStatus = 'Active'  AND i.EntryStatus IN ('Granted', 'Expired'))
                OR (d.EntryStatus = 'Granted' AND i.EntryStatus IN ('Fulfilled', 'Expired'))
                OR (d.EntryStatus = i.EntryStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50007, 'BR49 Violation: Chuyen doi trang thai WaitlistEntry khong hop le.', 1;
    END
END;
GO

-- --- QueueEntry ---
CREATE OR ALTER TRIGGER TRG_QueueEntry_StateTransition
ON QueueEntry
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(QueueStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.QueueEntryID = i.QueueEntryID
        WHERE  NOT (
                   (d.QueueStatus = 'Waiting'  AND i.QueueStatus IN ('Admitted', 'Expired'))
                OR (d.QueueStatus = 'Admitted' AND i.QueueStatus IN ('Exited'))
                OR (d.QueueStatus = i.QueueStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50008, 'BR49 Violation: Chuyen doi trang thai QueueEntry khong hop le.', 1;
    END
END;
GO

-- --- Waitlist ---
CREATE OR ALTER TRIGGER TRG_Waitlist_StateTransition
ON Waitlist
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(WaitlistStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.WaitlistID = i.WaitlistID
        WHERE  -- Valid transitions: Open->Closed only; Closed is terminal (§10.1)
               NOT (
                   (d.WaitlistStatus = 'Open' AND i.WaitlistStatus IN ('Closed'))
                OR (d.WaitlistStatus = i.WaitlistStatus) -- no-op update allowed
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50009, 'BR49 Violation: Chuyen doi trang thai Waitlist khong hop le.', 1;
    END
END;
GO

-- --- Queue ---
CREATE OR ALTER TRIGGER TRG_Queue_StateTransition
ON Queue
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(QueueStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.QueueID = i.QueueID
        WHERE  -- Valid transitions: Open->Closed only; Closed is terminal (§10.1)
               NOT (
                   (d.QueueStatus = 'Open' AND i.QueueStatus IN ('Closed'))
                OR (d.QueueStatus = i.QueueStatus) -- no-op update allowed
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50010, 'BR49 Violation: Chuyen doi trang thai Queue khong hop le.', 1;
    END
END;
GO

