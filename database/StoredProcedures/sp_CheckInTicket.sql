-- ============================================================
-- sp_CheckInTicket (BP9 / FR41-FR45 / BR28-BR30)
-- Xac thuc Ticket va ghi nhan Check-in tai cong vao Concert.
-- Transaction bao gom:
--   1. Tim Ticket theo TicketCode va ConcertID.
--   2. Kiem tra trang thai Ticket (phai la 'Issued').
--   3. Kiem tra Staff co quyen check-in Concert nay.
--   4. Neu hop le -> Ticket->Used, INSERT CheckIn, ghi Audit ADMISSION_SUCCESS.
--   5. Neu khong hop le -> ghi Audit ADMISSION_ATTEMPT (that bai).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CheckInTicket
(
    @TicketCode          VARCHAR(64),
    @ConcertID           INT,
    @CheckInStaffUserID  INT,
    @ValidationResult    VARCHAR(32) OUTPUT,
    @ValidationInfo      NVARCHAR(500) OUTPUT,
    -- Thoi diem check-in DA GHI VAO CheckIn.CheckInTimestamp. Tra ra ngoai de tang
    -- ung dung KHONG phai tu sinh mot moc thoi gian khac: truoc day
    -- CheckInRepository dung DateTime.UtcNow, tuc bao cao mot gia tri do chinh no
    -- bia ra sau khi SP da chay xong, khong phai gia tri thuc su duoc luu. Hai con
    -- so lech nhau dung bang do tre khu hoi, va khong doi chieu duoc voi ban ghi.
    -- Co gia tri mac dinh NULL nen moi lenh goi cu van chay duoc khong can sua.
    -- NULL khi khong check-in duoc (khong co ban ghi CheckIn nao duoc tao).
    @CheckInTimestamp    DATETIME2(7) = NULL OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    SET @ValidationResult  = 'FAILED';
    SET @ValidationInfo    = '';
    SET @CheckInTimestamp  = NULL;

    BEGIN TRY
        DECLARE @TranCounter INT = @@TRANCOUNT;
        IF @TranCounter > 0
            SAVE TRANSACTION sp_CheckInTicket_Save;
        ELSE
            BEGIN TRANSACTION;

        -- 1. Tim Ticket theo TicketCode
        DECLARE @TicketID     INT;
        DECLARE @TicketStatus VARCHAR(32);
        DECLARE @EventSeatID  INT;
        DECLARE @TicketConcert INT;

        SELECT @TicketID      = TicketID,
               @TicketStatus  = TicketStatus,
               @EventSeatID   = EventSeatID,
               @TicketConcert = ConcertID
        FROM   Ticket WITH (UPDLOCK)
        WHERE  TicketCode = @TicketCode;

        -- 2. Kiem tra Ticket ton tai
        IF @TicketID IS NULL
        BEGIN
            SET @ValidationResult = 'INVALID';
            SET @ValidationInfo   = 'Ticket code khong ton tai trong he thong.';
            GOTO AuditAndExit;
        END

        -- 3. Kiem tra Ticket thuoc dung Concert
        IF @TicketConcert <> @ConcertID
        BEGIN
            SET @ValidationResult = 'WRONG_EVENT';
            SET @ValidationInfo   = 'Ticket khong thuoc Concert nay.';
            GOTO AuditAndExit;
        END

        -- 4. Kiem tra trang thai Ticket (phai la Issued - BR28)
        IF @TicketStatus = 'Used'
        BEGIN
            SET @ValidationResult = 'ALREADY_USED';
            SET @ValidationInfo   = 'Ticket da duoc su dung truoc do.';
            GOTO AuditAndExit;
        END

        IF @TicketStatus = 'Cancelled'
        BEGIN
            SET @ValidationResult = 'CANCELLED';
            SET @ValidationInfo   = 'Ticket da bi huy.';
            GOTO AuditAndExit;
        END

        IF @TicketStatus <> 'Issued'
        BEGIN
            SET @ValidationResult = 'INVALID_STATUS';
            SET @ValidationInfo   = 'Ticket khong o trang thai hop le de check-in.';
            GOTO AuditAndExit;
        END

        -- 5. Kiem tra Staff co quyen check-in Concert nay (BR39)
        IF NOT EXISTS (
            SELECT 1 FROM CheckinStaffAssignment
            WHERE  UserID    = @CheckInStaffUserID
              AND  ConcertID = @ConcertID
              AND  AssignmentStatus = 'Active'
        )
        BEGIN
            SET @ValidationResult = 'UNAUTHORIZED';
            SET @ValidationInfo   = 'Staff khong co quyen hoac bi thu hoi quyen check-in Concert nay.';
            GOTO AuditAndExit;
        END

        -- 6. Kiem tra chua co CheckIn nao cho Ticket nay (BR29)
        IF EXISTS (
            SELECT 1 FROM CheckIn WHERE TicketID = @TicketID
        )
        BEGIN
            SET @ValidationResult = 'DUPLICATE_CHECKIN';
            SET @ValidationInfo   = 'Ticket da duoc check-in truoc do.';
            GOTO AuditAndExit;
        END

        -- --- CHECK-IN THANH CONG ---

        -- MOT su kien vao cong = MOT moc thoi gian.
        -- Truoc day ba ban ghi cua cung mot lan soat ve (Ticket.UsedTimestamp,
        -- CheckIn.CheckInTimestamp, AuditRecord.EventTimestamp) moi cai goi
        -- SYSDATETIME() rieng. SQL Server danh gia lai ham nay o TUNG LENH, nen ba
        -- moc co the lech nhau - dung thu ma nhat ky kiem toan ton tai de doi chieu.
        DECLARE @Now DATETIME2(7) = SYSDATETIME();

        -- 7. Chuyen Ticket -> Used
        UPDATE Ticket
        SET    TicketStatus   = 'Used',
               UsedTimestamp  = @Now
        WHERE  TicketID = @TicketID;

        -- 8. INSERT CheckIn record
        INSERT INTO CheckIn
            (TicketID, ConcertID, CheckInStaffUserID,
             CheckInTimestamp, ValidationResult, ValidationInformation)
        VALUES
            (@TicketID, @ConcertID, @CheckInStaffUserID,
             @Now, 'SUCCESS', 'Ticket hop le, da check-in thanh cong.');

        SET @ValidationResult = 'SUCCESS';
        SET @ValidationInfo   = 'Check-in thanh cong.';
        SET @CheckInTimestamp = @Now;   -- tra ra dung gia tri VUA GHI, khong phai mot moc moi

        -- 9. Ghi AuditRecord - ADMISSION_SUCCESS
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@CheckInStaffUserID, 'ADMISSION_SUCCESS', 'Ticket',
             CAST(@TicketID AS VARCHAR(64)), 'UPDATE',
             @Now,
             '{"TicketStatus":"Used","ValidationResult":"SUCCESS"}');

        IF @TranCounter = 0
            COMMIT TRANSACTION;
        RETURN;

        AuditAndExit:
        -- 10. Ghi AuditRecord - ADMISSION_ATTEMPT (that bai)
        IF @TranCounter = 0
            ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() <> -1
            ROLLBACK TRANSACTION sp_CheckInTicket_Save;

        -- Khi insert AuditRecord that bai, ta khong can Transaction, hoac dung 1 Transaction doc lap
        BEGIN TRANSACTION;
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@CheckInStaffUserID,
             'ADMISSION_ATTEMPT',
             'Ticket',
             ISNULL(CAST(@TicketID AS VARCHAR(64)), @TicketCode),
             'READ',
             SYSDATETIME(),
             '{"ValidationResult":"' + @ValidationResult + '","Info":"' + @ValidationInfo + '"}');
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @TranCounter = 0
            IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        ELSE IF XACT_STATE() <> -1
            ROLLBACK TRANSACTION sp_CheckInTicket_Save;
        THROW;
    END CATCH
END;
GO
