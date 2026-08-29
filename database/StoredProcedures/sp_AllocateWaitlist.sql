-- ============================================================
-- sp_AllocateWaitlist (BP10 / SIP2 / BR42-BR44)
-- Phan bo co hoi Booking cho Customer trong Waitlist theo
-- FIFO (JoinedTimestamp tang dan - BR43).
-- Xu ly cho mot Concert cu the khi EventSeat duoc giai phong.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AllocateWaitlist
(
    @ConcertID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    -- ----------------------------------------------------------------
    -- Tất cả biến khai báo tại đây (không khai báo trong loop)
    -- ----------------------------------------------------------------
    DECLARE @SystemUserID        INT;
    DECLARE @Now                 DATETIME2(7) = SYSDATETIME();
    DECLARE @OpportunityDuration INT;
    DECLARE @WaitlistID          INT;
    DECLARE @PurchaseLimit       INT;
    DECLARE @LockResource        NVARCHAR(128);
    DECLARE @LockResult          INT;
    DECLARE @BatchSize           INT = 50;
    DECLARE @MatchedCount        INT;
    DECLARE @EligibleCount       INT;
    DECLARE @OpportunityExpiry   DATETIME2(7);
    DECLARE @GrantedThisBatch    INT;

    SELECT @SystemUserID = UserID FROM UserAccount WHERE Username = 'system';

    SELECT @OpportunityDuration = CAST(ConfigurationValue AS INT)
    FROM   SystemConfiguration
    WHERE  ConfigurationKey = 'Waitlist_Opportunity_Duration';
    SET @OpportunityDuration = ISNULL(@OpportunityDuration, 3600);

    -- Pre-flight checks (ngoài transaction, nhanh)
    IF NOT EXISTS (
        SELECT 1 FROM Concert
        WHERE  ConcertID    = @ConcertID
          AND  ConcertStatus = 'OnSale'
          AND  SalesPaused   = 0
    ) RETURN;

    SELECT @WaitlistID = WaitlistID FROM Waitlist
    WHERE  ConcertID     = @ConcertID
      AND  WaitlistStatus = 'Open';
    IF @WaitlistID IS NULL RETURN;

    SELECT @PurchaseLimit = PurchaseLimit FROM Concert WHERE ConcertID = @ConcertID;

    -- ----------------------------------------------------------------
    -- Xin Application Lock cho Concert này
    -- Timeout = 0: Không chờ. Nếu luồng khác đang xử lý -> ra về ngay.
    -- ----------------------------------------------------------------
    SET @LockResource = 'WaitlistAlloc_' + CAST(@ConcertID AS NVARCHAR(10));

    EXEC @LockResult = sp_getapplock
        @Resource    = @LockResource,
        @LockMode    = 'Exclusive',
        @LockOwner   = 'Session',
        @LockTimeout = 0;

    IF @LockResult < 0 RETURN; -- Luồng khác đang lo rồi

    -- ----------------------------------------------------------------
    -- Vòng lặp Batch Allocation (chỉ 1 luồng chạy tại mọi thời điểm)
    -- ----------------------------------------------------------------
    BEGIN TRY
        SET @GrantedThisBatch = 1; -- Khởi tạo > 0 để vào loop

        WHILE @GrantedThisBatch > 0
        BEGIN
            -- Bước 1: Lấy N ghế trống
            -- UPDLOCK + READPAST: "nhảy cóc" qua ghế đang bị sp_CreateBooking giữ
            SELECT TOP (@BatchSize)
                   EventSeatID,
                   ROW_NUMBER() OVER (ORDER BY EventSeatID) AS RowNum
            INTO   #AvailableSeats
            FROM   EventSeat WITH (UPDLOCK, READPAST)
            WHERE  ConcertID       = @ConcertID
              AND  InventoryStatus = 'Available';

            SET @MatchedCount = @@ROWCOUNT;

            IF @MatchedCount = 0
            BEGIN
                IF OBJECT_ID('tempdb..#AvailableSeats') IS NOT NULL DROP TABLE #AvailableSeats;
                BREAK; -- Hết ghế
            END

            -- Bước 2: Lấy N người đầu hàng thỏa mãn Limit (FIFO nghiêm ngặt)
            -- Bổ sung WITH (UPDLOCK) để chặn User Cancel giữa chừng (Tránh Ghost Resurrection)
            SELECT TOP (@MatchedCount)
                   we.WaitlistEntryID,
                   ROW_NUMBER() OVER (ORDER BY we.JoinedTimestamp ASC) AS RowNum
            INTO   #EligibleUsers
            FROM   WaitlistEntry we WITH (UPDLOCK)
            CROSS APPLY dbo.fn_GetCustomerTicketCount(we.CustomerUserID, @ConcertID) tc
            WHERE  we.WaitlistID  = @WaitlistID
              AND  we.EntryStatus = 'Active'
              AND  (tc.TicketCount + 1) <= @PurchaseLimit
            ORDER BY we.JoinedTimestamp ASC;

            SET @EligibleCount = @@ROWCOUNT;

            IF @EligibleCount = 0
            BEGIN
                IF OBJECT_ID('tempdb..#AvailableSeats') IS NOT NULL DROP TABLE #AvailableSeats;
                IF OBJECT_ID('tempdb..#EligibleUsers') IS NOT NULL DROP TABLE #EligibleUsers;
                BREAK; -- Hết người hợp lệ
            END

            -- Bước 3: Ghép cặp và cập nhật trong 1 Transaction nguyên tử
            BEGIN TRANSACTION;

            SET @OpportunityExpiry = DATEADD(SECOND, @OpportunityDuration, @Now);

            UPDATE es
            SET    InventoryStatus = 'OnHoldForWaitlist'
            FROM   EventSeat es
            JOIN   #AvailableSeats a ON es.EventSeatID = a.EventSeatID
            JOIN   #EligibleUsers  u ON a.RowNum       = u.RowNum;

            UPDATE we
            SET    EntryStatus                = 'Granted',
                   OpportunityGrantedTimestamp = @Now,
                   OpportunityExpiryTimestamp  = @OpportunityExpiry,
                   OfferedEventSeatID          = a.EventSeatID
            FROM   WaitlistEntry we
            JOIN   #EligibleUsers  u ON we.WaitlistEntryID = u.WaitlistEntryID
            JOIN   #AvailableSeats a ON u.RowNum = a.RowNum;

            -- @@ROWCOUNT lấy ngay từ UPDATE WaitlistEntry (trước khi có lệnh khác)
            SET @GrantedThisBatch = @@ROWCOUNT;

            -- Bulk Audit (tất cả cặp được cấp trong batch này)
            INSERT INTO AuditRecord
                (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            SELECT @SystemUserID,
                   'SYSTEM_WAITLIST_OPPORTUNITY_GRANTED',
                   'WaitlistEntry',
                   CAST(u.WaitlistEntryID AS VARCHAR(64)),
                   'UPDATE',
                   @Now,
                   '{"EntryStatus":"Granted","OfferedEventSeatID":' + CAST(a.EventSeatID AS VARCHAR) + '}'
            FROM   #EligibleUsers u
            JOIN   #AvailableSeats a ON u.RowNum = a.RowNum;

            COMMIT TRANSACTION; -- COMMIT trước khi DROP

            IF OBJECT_ID('tempdb..#AvailableSeats') IS NOT NULL DROP TABLE #AvailableSeats;
            IF OBJECT_ID('tempdb..#EligibleUsers') IS NOT NULL DROP TABLE #EligibleUsers;
        END -- WHILE

        EXEC sp_releaseapplock @Resource = @LockResource, @LockOwner = 'Session';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        -- Cleanup temp tables an toàn
        IF OBJECT_ID('tempdb..#AvailableSeats') IS NOT NULL DROP TABLE #AvailableSeats;
        IF OBJECT_ID('tempdb..#EligibleUsers')  IS NOT NULL DROP TABLE #EligibleUsers;
        -- Nhả khóa dù có lỗi
        EXEC sp_releaseapplock @Resource = @LockResource, @LockOwner = 'Session';
        THROW;
    END CATCH
END;
GO
