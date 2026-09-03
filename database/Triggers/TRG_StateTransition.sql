-- ============================================================
-- TRG_StateTransition
-- Kiem tra moi chuyen doi trang thai (OLD -> NEW) hop le
-- theo state machine duoc dinh nghia tai §10.1 (BR49).
-- Ap dung cho: Concert, EventSeat, Booking, Payment,
--              Ticket, Refund, Waitlist, WaitlistEntry,
--              Queue, QueueEntry.
-- (Da cap nhat AFTER INSERT, UPDATE va validate init state)
-- ============================================================

-- --- Concert ---
CREATE OR ALTER TRIGGER TRG_Concert_StateTransition
ON Concert
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(ConcertStatus) RETURN;

    -- Validate initial state for INSERT
    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.ConcertID = i.ConcertID
        WHERE  d.ConcertID IS NULL AND i.ConcertStatus <> 'Draft'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50001, 'BR49 Violation: Trang thai khoi tao cua Concert phai la Draft.', 1;
    END

    -- Validate transitions for UPDATE
    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.ConcertID = i.ConcertID
        WHERE  NOT (
                   (d.ConcertStatus = 'Draft'       AND i.ConcertStatus IN ('Published', 'Cancelled'))
                OR (d.ConcertStatus = 'Published'   AND i.ConcertStatus IN ('OnSale', 'Cancelled'))
                OR (d.ConcertStatus = 'OnSale'      AND i.ConcertStatus IN ('SaleClosed', 'Cancelled'))
                OR (d.ConcertStatus = 'SaleClosed'  AND i.ConcertStatus IN ('Completed', 'Cancelled', 'OnSale'))
                OR (d.ConcertStatus = i.ConcertStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50001, 'BR49 Violation: Chuyen doi trang thai Concert khong hop le.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.ConcertID = i.ConcertID
        WHERE  d.ConcertStatus = 'Draft' AND i.ConcertStatus = 'Published'
          AND  (i.OrganizerUserID IS NULL OR i.ArtistID IS NULL OR i.VenueID IS NULL
                OR i.StartDatetime IS NULL OR i.EndDatetime IS NULL
                OR i.EndDatetime <= i.StartDatetime)
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50011, 'LI00/BR54 Violation: Concert chua du dieu kien de Published (thieu field hoac End <= Start).', 1;
    END
END;
GO

-- --- Booking ---
CREATE OR ALTER TRIGGER TRG_Booking_StateTransition
ON Booking
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(BookingStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.BookingID = i.BookingID
        WHERE  d.BookingID IS NULL AND i.BookingStatus <> 'Pending'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50002, 'BR49 Violation: Trang thai khoi tao cua Booking phai la Pending.', 1;
    END

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
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(PaymentStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.PaymentID = i.PaymentID
        WHERE  d.PaymentID IS NULL AND i.PaymentStatus <> 'Pending'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50003, 'BR49 Violation: Trang thai khoi tao cua Payment phai la Pending.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.PaymentID = i.PaymentID
        WHERE  NOT (
                   (d.PaymentStatus = 'Pending'   AND i.PaymentStatus IN ('Confirmed', 'Failed'))
                OR (d.PaymentStatus = 'Confirmed' AND i.PaymentStatus IN ('PartiallyRefunded', 'Refunded'))
                OR (d.PaymentStatus = 'PartiallyRefunded' AND i.PaymentStatus IN ('PartiallyRefunded', 'Refunded'))
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
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(TicketStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.TicketID = i.TicketID
        WHERE  d.TicketID IS NULL AND i.TicketStatus <> 'Issued'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50004, 'BR49 Violation: Trang thai khoi tao cua Ticket phai la Issued.', 1;
    END

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
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(InventoryStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.EventSeatID = i.EventSeatID
        WHERE  d.EventSeatID IS NULL AND i.InventoryStatus <> 'Available'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50005, 'BR49 Violation: Trang thai khoi tao cua EventSeat phai la Available.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.EventSeatID = i.EventSeatID
        WHERE  NOT (
                   (d.InventoryStatus = 'Available'         AND i.InventoryStatus IN ('OnHold', 'OnHoldForWaitlist', 'Unavailable', 'Booked'))
                OR (d.InventoryStatus = 'OnHold'            AND i.InventoryStatus IN ('Available', 'Booked', 'OnHoldForWaitlist'))
                OR (d.InventoryStatus = 'OnHoldForWaitlist' AND i.InventoryStatus IN ('Available', 'OnHold', 'OnHoldForWaitlist', 'Booked'))
                OR (d.InventoryStatus = 'Booked'            AND i.InventoryStatus IN ('Available', 'OnHoldForWaitlist'))
                OR (d.InventoryStatus = 'Unavailable'       AND i.InventoryStatus IN ('Available'))
                OR (d.InventoryStatus = i.InventoryStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50005, 'BR49 Violation: Chuyen doi trang thai EventSeat khong hop le.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.EventSeatID = i.EventSeatID
        JOIN   Concert c ON c.ConcertID = i.ConcertID
        WHERE  d.InventoryStatus = 'Unavailable' AND i.InventoryStatus = 'Available'
          AND  c.ConcertStatus NOT IN ('Draft', 'Published', 'OnSale')
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50015, 'CI08 Violation: Khong the chuyen Unavailable -> Available khi Concert khong o trang thai Draft/Published/OnSale.', 1;
    END
END;
GO

-- --- Refund ---
CREATE OR ALTER TRIGGER TRG_Refund_StateTransition
ON Refund
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(RefundStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.RefundID = i.RefundID
        WHERE  d.RefundID IS NULL AND i.RefundStatus NOT IN ('Pending', 'Confirmed')
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50006, 'BR49 Violation: Trang thai khoi tao cua Refund phai la Pending hoac Confirmed.', 1;
    END

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
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(EntryStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.WaitlistEntryID = i.WaitlistEntryID
        WHERE  d.WaitlistEntryID IS NULL AND i.EntryStatus <> 'Active'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50007, 'BR49 Violation: Trang thai khoi tao cua WaitlistEntry phai la Active.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.WaitlistEntryID = i.WaitlistEntryID
        WHERE  NOT (
                   (d.EntryStatus = 'Active'  AND i.EntryStatus IN ('Granted', 'Expired', 'Cancelled'))
                OR (d.EntryStatus = 'Granted' AND i.EntryStatus IN ('Fulfilled', 'Expired', 'Cancelled'))
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
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(QueueStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.QueueEntryID = i.QueueEntryID
        WHERE  d.QueueEntryID IS NULL AND i.QueueStatus <> 'Waiting'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50008, 'BR49 Violation: Trang thai khoi tao cua QueueEntry phai la Waiting.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.QueueEntryID = i.QueueEntryID
        WHERE  NOT (
                   (d.QueueStatus = 'Waiting'  AND i.QueueStatus IN ('Admitted', 'Expired', 'Cancelled', 'Exited'))
                OR (d.QueueStatus = 'Admitted' AND i.QueueStatus IN ('Exited', 'Expired', 'Cancelled'))
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
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(WaitlistStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.WaitlistID = i.WaitlistID
        WHERE  d.WaitlistID IS NULL AND i.WaitlistStatus <> 'Open'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50009, 'BR49 Violation: Trang thai khoi tao cua Waitlist phai la Open.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.WaitlistID = i.WaitlistID
        WHERE  NOT (
                   (d.WaitlistStatus = 'Open' AND i.WaitlistStatus IN ('Closed'))
                OR (d.WaitlistStatus = i.WaitlistStatus)
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
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(QueueStatus) RETURN;

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        LEFT JOIN deleted d ON d.QueueID = i.QueueID
        WHERE  d.QueueID IS NULL AND i.QueueStatus <> 'Open'
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50010, 'BR49 Violation: Trang thai khoi tao cua Queue phai la Open.', 1;
    END

    IF EXISTS (
        SELECT 1
        FROM   inserted i
        JOIN   deleted  d ON d.QueueID = i.QueueID
        WHERE  NOT (
                   (d.QueueStatus = 'Open' AND i.QueueStatus IN ('Closed'))
                OR (d.QueueStatus = i.QueueStatus)
               )
    )
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50010, 'BR49 Violation: Chuyen doi trang thai Queue khong hop le.', 1;
    END
END;
GO
