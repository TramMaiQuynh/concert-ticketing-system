-- ============================================================
-- sp_AllocateWaitlist (BP10 / SIP2 / BR42-BR44)
-- Phan bo co hoi Booking cho Customer trong Waitlist theo
-- AllocationPolicy (FIFO hoac RANDOM).
-- Xu ly cho mot Concert cu the khi EventSeat duoc giai phong.
-- Tuan thu nghiem ngat all-or-nothing (RequestedQuantity) va
-- khong skip-ahead trong cung TicketCategory (CI07).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AllocateWaitlist
(
    @ConcertID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID        INT;
    DECLARE @Now                 DATETIME2(7) = SYSDATETIME();
    DECLARE @OpportunityDuration INT;
    DECLARE @WaitlistID          INT;
    DECLARE @PurchaseLimit       INT;
    DECLARE @FairAccessPolicy    VARCHAR(32);
    DECLARE @LockResource        NVARCHAR(128);
    DECLARE @LockResult          INT;

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

    SELECT @WaitlistID = WaitlistID, @FairAccessPolicy = ISNULL(AllocationPolicy, 'FIFO')
    FROM   Waitlist
    WHERE  ConcertID      = @ConcertID
      AND  WaitlistStatus = 'Open';

    IF @WaitlistID IS NULL RETURN;

    SELECT @PurchaseLimit = PurchaseLimit FROM Concert WHERE ConcertID = @ConcertID;

    -- ----------------------------------------------------------------
    -- Xin Application Lock cho Concert này
    -- ----------------------------------------------------------------
    SET @LockResource = 'WaitlistAlloc_' + CAST(@ConcertID AS NVARCHAR(10));

    EXEC @LockResult = sp_getapplock
        @Resource    = @LockResource,
        @LockMode    = 'Exclusive',
        @LockOwner   = 'Session',
        @LockTimeout = 0;

    IF @LockResult < 0 RETURN;

    BEGIN TRY
        -- Giai phong cac hold het han truoc khi cap phat (CRIT-12)
        EXEC dbo.sp_ReleaseExpiredHolds @ConcertID = @ConcertID;

        -- Dem so ghe Available theo tung Category hien tai
        CREATE TABLE #CategoryState (
            TicketCategoryID INT PRIMARY KEY,
            AvailableCount INT,
            IsBlocked BIT
        );

        INSERT INTO #CategoryState (TicketCategoryID, AvailableCount, IsBlocked)
        SELECT TicketCategoryID, COUNT(*), 0
        FROM EventSeat WITH (UPDLOCK, READPAST)
        WHERE ConcertID = @ConcertID AND InventoryStatus = 'Available'
        GROUP BY TicketCategoryID;

        DECLARE @EntryID INT, @CustomerID INT, @CategoryID INT, @ReqQty INT;
        DECLARE @AllocatedSeats TABLE (EventSeatID INT); -- Thay the #AllocatedSeats (I-03)

        -- Mo Cursor de duyet tung WaitlistEntry
        DECLARE @Sql NVARCHAR(MAX);
        IF @FairAccessPolicy = 'RANDOM'
        BEGIN
            DECLARE cWaitlist CURSOR LOCAL FAST_FORWARD FOR
            SELECT WaitlistEntryID, CustomerUserID, TicketCategoryID, RequestedQuantity
            FROM WaitlistEntry
            WHERE WaitlistID = @WaitlistID AND EntryStatus = 'Active'
            ORDER BY NEWID();
        END
        ELSE
        BEGIN
            DECLARE cWaitlist CURSOR LOCAL FAST_FORWARD FOR
            SELECT WaitlistEntryID, CustomerUserID, TicketCategoryID, RequestedQuantity
            FROM WaitlistEntry
            WHERE WaitlistID = @WaitlistID AND EntryStatus = 'Active'
            ORDER BY JoinedTimestamp ASC;
        END

        OPEN cWaitlist;
        FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- 1. Kiem tra Category da bi block chua (No skip-ahead CI07)
            DECLARE @Avail INT = 0, @IsBlocked BIT = 0;
            SELECT @Avail = AvailableCount, @IsBlocked = IsBlocked
            FROM #CategoryState WHERE TicketCategoryID = @CategoryID;

            IF @IsBlocked = 1
            BEGIN
                FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
                CONTINUE;
            END

            -- 2. Kiem tra du so luong RequestedQuantity (All-or-nothing BR42b)
            IF @ReqQty > @Avail
            BEGIN
                UPDATE #CategoryState SET IsBlocked = 1 WHERE TicketCategoryID = @CategoryID;
                FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
                CONTINUE;
            END

            -- 3. Kiem tra Purchase Limit
            DECLARE @ExistingCount INT;
            SELECT @ExistingCount = TicketCount 
            FROM dbo.fn_GetCustomerTicketCount(@CustomerID, @ConcertID);
            
            IF (@ExistingCount + @ReqQty) > @PurchaseLimit
            BEGIN
                FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
                CONTINUE;
            END

            -- 4. Tien hanh cap phat
            BEGIN TRANSACTION;
            
            DELETE FROM @AllocatedSeats;
            
            INSERT INTO @AllocatedSeats (EventSeatID)
            SELECT TOP (@ReqQty) EventSeatID
            FROM EventSeat WITH (UPDLOCK, READPAST)
            WHERE ConcertID = @ConcertID AND TicketCategoryID = @CategoryID AND InventoryStatus = 'Available';

            IF (SELECT COUNT(*) FROM @AllocatedSeats) = @ReqQty
            BEGIN
                DECLARE @Expiry DATETIME2(7) = DATEADD(SECOND, @OpportunityDuration, @Now);

                -- Update EventSeat
                UPDATE EventSeat 
                SET InventoryStatus = 'OnHoldForWaitlist' 
                WHERE EventSeatID IN (SELECT EventSeatID FROM @AllocatedSeats);
                
                -- Update WaitlistEntry
                UPDATE WaitlistEntry 
                SET EntryStatus = 'Granted', 
                    OpportunityGrantedTimestamp = @Now, 
                    OpportunityExpiryTimestamp = @Expiry 
                WHERE WaitlistEntryID = @EntryID;
                
                -- Insert WaitlistEntryEventSeatAllocation
                INSERT INTO WaitlistEntryEventSeatAllocation (WaitlistEntryID, EventSeatID, AllocationTimestamp, AllocationStatus)
                SELECT @EntryID, EventSeatID, @Now, 'Active' 
                FROM @AllocatedSeats;
                
                -- Cap nhat bien trong memory
                UPDATE #CategoryState SET AvailableCount = AvailableCount - @ReqQty WHERE TicketCategoryID = @CategoryID;

                -- Ghi Audit
                DECLARE @SeatIDsCSV NVARCHAR(MAX);
                SELECT @SeatIDsCSV = STRING_AGG(CAST(EventSeatID AS VARCHAR), ',') FROM @AllocatedSeats;

                INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
                VALUES (@SystemUserID, 'SYSTEM_WAITLIST_OPPORTUNITY_GRANTED', 'WaitlistEntry', CAST(@EntryID AS VARCHAR(64)), 'UPDATE', @Now,
                        '{"EntryStatus":"Granted","EventSeatIDs":"' + @SeatIDsCSV + '"}');

                COMMIT TRANSACTION;
            END
            ELSE
            BEGIN
                ROLLBACK TRANSACTION;
                UPDATE #CategoryState SET IsBlocked = 1 WHERE TicketCategoryID = @CategoryID;
            END

            FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
        END

        CLOSE cWaitlist;
        DEALLOCATE cWaitlist;
        DROP TABLE #CategoryState;

        EXEC sp_releaseapplock @Resource = @LockResource, @LockOwner = 'Session';

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        IF OBJECT_ID('tempdb..#CategoryState') IS NOT NULL DROP TABLE #CategoryState;
        
        IF CURSOR_STATUS('local','cWaitlist') >= -1 
        BEGIN
            IF CURSOR_STATUS('local','cWaitlist') > -1 CLOSE cWaitlist;
            DEALLOCATE cWaitlist;
        END

        EXEC sp_releaseapplock @Resource = @LockResource, @LockOwner = 'Session';
        THROW;
    END CATCH
END;
GO
