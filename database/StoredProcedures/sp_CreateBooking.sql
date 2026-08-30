-- ============================================================
-- sp_CreateBooking (BP5 / BR11-BR21 / FR17-FR22 / CI04)
-- Tao Booking va giu cac EventSeat theo co che Temporary Hold.
-- Toan bo xu ly duoc thuc hien trong mot Transaction:
--   1. Kiem tra Concert OnSale va khong bi SalesPaused.
--   2. Kiem tra Purchase Limit.
--   3. Giu tung EventSeat bang conditional UPDATE (chong oversell).
--   4. Tao Booking va cac Allocation.
--   5. Ghi AuditRecord.
-- @SeatList: chuoi EventSeatID phan cach bang dau phay.
-- ============================================================
CREATE PROCEDURE dbo.sp_CreateBooking
(
    @CustomerUserID  INT,
    @ConcertID       INT,
    @SeatList        NVARCHAR(MAX),   -- vd: '101,102,103'
    @WaitlistEntryID INT = NULL,
    @NewBookingID    INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- --------------------------------------------------------
        -- 1. Kiem tra Concert phai o trang thai OnSale
        --    va chua bi tam dung ban (SalesPaused = 0)
        -- --------------------------------------------------------
        IF NOT EXISTS (
            SELECT 1 FROM Concert
            WHERE  ConcertID    = @ConcertID
              AND  ConcertStatus = 'OnSale'
              AND  SalesPaused   = 0
        )
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51001, 'sp_CreateBooking: Concert khong o trang thai OnSale hoac dang tam dung ban ve.', 1;
        END

        -- --------------------------------------------------------
        -- 2. Phan tich danh sach SeatID tu chuoi -> bang tam
        -- --------------------------------------------------------
        CREATE TABLE #SeatRequests (EventSeatID INT NOT NULL);

        DECLARE @OfferedEventSeatID INT;

        IF @WaitlistEntryID IS NOT NULL
        BEGIN
            -- Luong Waitlist: Khach hang dang dung co hoi Waitlist de mua ve
            SELECT @OfferedEventSeatID = OfferedEventSeatID
            FROM   WaitlistEntry
            WHERE  WaitlistEntryID = @WaitlistEntryID
              AND  CustomerUserID  = @CustomerUserID
              AND  EntryStatus     = 'Granted'
              AND  OpportunityExpiryTimestamp >= SYSDATETIME();

            IF @OfferedEventSeatID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 51005, 'sp_CreateBooking: WaitlistEntry khong hop le, khong thuoc ve Customer, hoac da het han.', 1;
            END

            -- Bo qua @SeatList cua client, chi book dung cai ghe duoc offer
            INSERT INTO #SeatRequests (EventSeatID) VALUES (@OfferedEventSeatID);
        END
        ELSE
        BEGIN
            -- Luong binh thuong
            INSERT INTO #SeatRequests (EventSeatID)
            SELECT CAST(value AS INT)
            FROM   STRING_SPLIT(@SeatList, ',')
            WHERE  LTRIM(RTRIM(value)) <> '';
        END

        DECLARE @RequestedCount INT = (SELECT COUNT(*) FROM #SeatRequests);

        IF @RequestedCount = 0
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51002, 'sp_CreateBooking: Danh sach EventSeat rong.', 1;
        END

        -- --------------------------------------------------------
        -- 3. Kiem tra Purchase Limit (BR20)
        -- --------------------------------------------------------
        DECLARE @PurchaseLimit   INT;
        DECLARE @HoldDuration    INT;
        DECLARE @GlobalHoldDur   INT;

        SELECT @PurchaseLimit = PurchaseLimit,
               @HoldDuration  = TemporaryHoldDuration
        FROM   Concert
        WHERE  ConcertID = @ConcertID;

        IF @HoldDuration IS NULL
        BEGIN
            SELECT @GlobalHoldDur = CAST(ConfigurationValue AS INT)
            FROM   SystemConfiguration
            WHERE  ConfigurationKey = 'Default_Temporary_Hold_Duration';
            SET @HoldDuration = ISNULL(@GlobalHoldDur, 900);
        END

        DECLARE @ExistingCount INT;
        SELECT @ExistingCount = TicketCount 
        FROM dbo.fn_GetCustomerTicketCount(@CustomerUserID, @ConcertID);

        IF (@ExistingCount + @RequestedCount) > @PurchaseLimit
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51003, 'sp_CreateBooking: Vuot qua Purchase Limit cua Concert.', 1;
        END

        -- --------------------------------------------------------
        -- 4. Giu tung EventSeat bang conditional UPDATE (CI04)
        --    Neu bat ky Seat nao khong o trang thai Available -> ROLLBACK
        -- --------------------------------------------------------
        UPDATE EventSeat
        SET    InventoryStatus = 'OnHold'
        WHERE  EventSeatID     IN (SELECT EventSeatID FROM #SeatRequests)
          AND  ConcertID       = @ConcertID
          AND  InventoryStatus = CASE WHEN @WaitlistEntryID IS NOT NULL THEN 'OnHoldForWaitlist' ELSE 'Available' END;  -- conditional

        IF @@ROWCOUNT <> @RequestedCount
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51004, 'sp_CreateBooking: Mot hoac nhieu EventSeat khong con kha dung. Vui long chon lai.', 1;
        END

        -- --------------------------------------------------------
        -- 5. Tinh SubtotalAmount = SUM(SalePrice) cua cac seat duoc giu
        -- --------------------------------------------------------
        DECLARE @SubtotalAmount DECIMAL(18,0);
        SELECT @SubtotalAmount = SUM(SalePrice)
        FROM   EventSeat
        WHERE  EventSeatID IN (SELECT EventSeatID FROM #SeatRequests);

        -- --------------------------------------------------------
        -- 6. Tao Booking
        -- --------------------------------------------------------
        DECLARE @HoldStart  DATETIME2(7) = SYSDATETIME();
        DECLARE @HoldExpiry DATETIME2(7) = DATEADD(SECOND, @HoldDuration, @HoldStart);

        INSERT INTO Booking
            (CustomerUserID, ConcertID, BookingStatus,
             HoldStartDatetime, HoldExpiryDatetime,
             SubtotalAmount, FinalAmount, CreatedTimestamp)
        VALUES
            (@CustomerUserID, @ConcertID, 'Pending',
             @HoldStart, @HoldExpiry,
             @SubtotalAmount, @SubtotalAmount, @HoldStart);

        SET @NewBookingID = SCOPE_IDENTITY();

        -- --------------------------------------------------------
        -- 7. Tao cac Allocation
        -- --------------------------------------------------------
        INSERT INTO BookingEventSeatAllocation
            (BookingID, EventSeatID, AllocationTimestamp, AllocationStatus, PriceSnapshot)
        SELECT @NewBookingID,
               es.EventSeatID,
               @HoldStart,
               'Active',
               es.SalePrice
        FROM   EventSeat es
        JOIN   #SeatRequests sr ON sr.EventSeatID = es.EventSeatID;

        -- --------------------------------------------------------
        -- 8. Ghi AuditRecord
        -- --------------------------------------------------------
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@CustomerUserID, 'BOOKING_CREATED', 'Booking',
             CAST(@NewBookingID AS VARCHAR(64)), 'INSERT',
             SYSDATETIME(),
             '{"Status":"Pending","SeatCount":' + CAST(@RequestedCount AS VARCHAR) + '}');

        -- --------------------------------------------------------
        -- 9. Cap nhat WaitlistEntry neu co
        -- --------------------------------------------------------
        IF @WaitlistEntryID IS NOT NULL
        BEGIN
            UPDATE WaitlistEntry
            SET    EntryStatus = 'Fulfilled',
                   ResultingBookingID = @NewBookingID
            WHERE  WaitlistEntryID = @WaitlistEntryID;
        END

        DROP TABLE #SeatRequests;
        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#SeatRequests') IS NOT NULL DROP TABLE #SeatRequests;
        THROW;  -- Re-throw loi goc cho caller xu ly
    END CATCH
END;
GO
