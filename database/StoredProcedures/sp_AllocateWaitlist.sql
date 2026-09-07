-- ============================================================
-- sp_AllocateWaitlist (BP10 / SIP2 / BR42-BR44)
-- Phan bo co hoi Booking cho Customer trong Waitlist theo AllocationPolicy
-- (FIFO hoac RANDOM - BR43). Xu ly cho MOT Concert cu the.
-- Tuan thu nghiem ngat all-or-nothing theo RequestedQuantity (BR42b) va
-- khong skip-ahead trong cung TicketCategory (CI07).
--
-- ============================================================
-- GHI CHU THIET KE (sua lai o dot ra soat - bon van de that o ban truoc)
-- ============================================================
-- (1) APPLOCK BI RO. Ban truoc dung @LockOwner = 'Session' vi vong lap mo mot
--     transaction RIENG cho tung entry - khoa pham vi Transaction se bi nha ngay
--     o lan COMMIT dau tien. Hau qua: neu SP bi huy giua chung (client cancel,
--     timeout, kill session) thi khoa KHONG duoc nha; moi lan chay SIP2 sau do
--     cho Concert nay deu lang le thoat ra o `IF @LockResult < 0 RETURN`, tuc
--     waitlist ngung phan bo ma khong co dau hieu gi. No chi duoc don khi
--     connection bi reset ve pool - mot su phu thuoc vao hanh vi cua tang khac,
--     khong phai mot bao dam.
--     Nay: TOAN BO lan chay nam trong MOT transaction va khoa co pham vi
--     'Transaction'. Engine tu nha khoa khi COMMIT hoac ROLLBACK, ke ca khi
--     phien bi kill - khong con duong nao ro khoa.
--
-- (2) TRANSACTION LONG. Doi lai, mot transaction cho ca lan chay se giu khoa tren
--     EventSeat lau hon, ma sp_CreateBooking cung dung dung nhung dong do -> chan
--     khach dat ve. Xu ly bang cach GIOI HAN khoi luong moi lan chay
--     (@MaxEntriesPerRun): SIP2 la tien trinh dinh ky, xu ly het phan con lai o
--     lan chay ke tiep. Day la mau batch chuan: giao dich ngan, chay nhieu lan,
--     thay vi mot giao dich dai khong xac dinh do lon.
--
-- (3) GOI LONG sp_ReleaseExpiredHolds. Ban truoc goi SP nay ben trong khoi TRY.
--     Khi da nam trong transaction cua chinh minh, BEGIN/COMMIT cua SP con chi
--     lam tang/giam @@TRANCOUNT chu khong commit that; nguy hiem hon la nhanh
--     CATCH cua no (`IF @@TRANCOUNT > 0 ROLLBACK`) se ROLLBACK CA transaction cua
--     ta. Ve mat trach nhiem, giai phong hold het han la viec cua SIP1, khong phai
--     cua SIP2. Nay bo hoan toan: HoldReleaseWorker da goi sp_ReleaseExpiredHolds
--     TRUOC roi moi goi SP nay cho tung Concert - dung thu tu can co.
--
-- (4) HINT KHOA DAT SAI CHO. Cau dem ton kho theo Category dung (UPDLOCK, READPAST)
--     nhung chay NGOAI transaction nen UPDLOCK khong ton tai qua cau lenh. Nay cau
--     dem nam trong transaction va chi con READPAST: no la so lieu DINH HUONG de
--     quyet dinh thu tu/chan Category. Cong doan co thuc quyen van la lenh
--     `TOP (@ReqQty) ... WITH (UPDLOCK, READPAST)` ben duoi - do moi la noi gianh
--     ghe that su. Giu UPDLOCK o cau dem se khoa moi ghe Available cua Concert
--     trong suot lan chay, chan ca nguoi dang mua binh thuong, doi lay mot con so
--     ma dang nao cung phai kiem lai.
--
-- Vong lap CURSOR duoc GIU LAI co chu dich: CI07 doi hoi duyet tuan tu theo thu tu
-- chinh sach va DUNG LAI o entry dau tien khong du ghe trong cung Category. Do la
-- ngu nghia tuan tu ban chat, khong the viet lai thanh mot lenh set-based ma van
-- giu nguyen "khong skip-ahead".
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AllocateWaitlist
(
    @ConcertID         INT,
    -- Gioi han so WaitlistEntry duyet trong mot lan chay (xem ghi chu 2).
    -- SIP2 chay dinh ky nen phan du duoc xu ly o lan ke tiep.
    @MaxEntriesPerRun  INT = 50
)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SystemUserID        INT;
    DECLARE @Now                 DATETIME2(7) = SYSDATETIME();
    DECLARE @OpportunityDuration INT;
    DECLARE @WaitlistID          INT;
    DECLARE @PurchaseLimit       INT;
    DECLARE @AllocationPolicy    VARCHAR(32);
    DECLARE @LockResource        NVARCHAR(128);
    DECLARE @LockResult          INT;

    IF @MaxEntriesPerRun IS NULL OR @MaxEntriesPerRun <= 0
        SET @MaxEntriesPerRun = 50;

    SELECT @SystemUserID = UserID FROM UserAccount WHERE Username = 'system';

    SELECT @OpportunityDuration = CAST(ConfigurationValue AS INT)
    FROM   SystemConfiguration
    WHERE  ConfigurationKey = 'Waitlist_Opportunity_Duration';

    IF @OpportunityDuration IS NULL
        THROW 59701, 'sp_AllocateWaitlist: Thieu SystemConfiguration.Waitlist_Opportunity_Duration (§23.7).', 1;

    -- ----------------------------------------------------------------
    -- Pre-flight (ngoai transaction, re): khong co gi de lam thi thoat som
    -- ----------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1 FROM Concert
        WHERE  ConcertID     = @ConcertID
          AND  ConcertStatus = 'OnSale'
          AND  SalesPaused   = 0
    ) RETURN;

    SELECT @WaitlistID       = WaitlistID,
           @AllocationPolicy = ISNULL(AllocationPolicy, 'FIFO')
    FROM   Waitlist
    WHERE  ConcertID      = @ConcertID
      AND  WaitlistStatus = 'Open';

    IF @WaitlistID IS NULL RETURN;

    SELECT @PurchaseLimit = PurchaseLimit FROM Concert WHERE ConcertID = @ConcertID;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Khoa theo Concert, pham vi Transaction -> tu nha khi COMMIT/ROLLBACK.
        -- LockTimeout = 0: neu mot lan chay khac dang xu ly Concert nay thi bo qua
        -- ngay, vi day la tien trinh nen se chay lai o chu ky sau.
        SET @LockResource = 'WaitlistAlloc_' + CAST(@ConcertID AS NVARCHAR(20));

        EXEC @LockResult = sp_getapplock
            @Resource    = @LockResource,
            @LockMode    = 'Exclusive',
            @LockOwner   = 'Transaction',
            @LockTimeout = 0;

        IF @LockResult < 0
        BEGIN
            ROLLBACK TRANSACTION;
            RETURN;
        END

        -- ------------------------------------------------------------
        -- So ghe Available theo tung TicketCategory (so lieu dinh huong - ghi chu 4)
        -- READPAST: bo qua nhung ghe dang bi giao dich khac giu, vi chung khong
        -- thuc su kha dung cho lan phan bo nay.
        -- ------------------------------------------------------------
        CREATE TABLE #CategoryState (
            TicketCategoryID INT PRIMARY KEY,
            AvailableCount   INT NOT NULL,
            IsBlocked        BIT NOT NULL
        );

        INSERT INTO #CategoryState (TicketCategoryID, AvailableCount, IsBlocked)
        SELECT TicketCategoryID, COUNT(*), 0
        FROM   EventSeat WITH (READPAST)
        WHERE  ConcertID = @ConcertID AND InventoryStatus = 'Available'
        GROUP BY TicketCategoryID;

        DECLARE @EntryID INT, @CustomerID INT, @CategoryID INT, @ReqQty INT;
        DECLARE @AllocatedSeats TABLE (EventSeatID INT PRIMARY KEY);

        -- Mot khai bao cursor duy nhat; thu tu do chinh sach quyet dinh.
        -- Khi RANDOM: khoa sap xep thu nhat la NEWID() (ngau nhien tung dong),
        --             khoa thu hai la NULL cho moi dong nen khong anh huong.
        -- Khi FIFO  : khoa thu nhat la NULL cho moi dong, JoinedTimestamp quyet dinh.
        -- (Ban truoc dat HAI khoi DECLARE CURSOR trung ten trong hai nhanh IF/ELSE -
        --  chay duoc nhung la mot cau truc de gay nham lan khi bao tri.)
        DECLARE cWaitlist CURSOR LOCAL FAST_FORWARD FOR
            SELECT TOP (@MaxEntriesPerRun)
                   WaitlistEntryID, CustomerUserID, TicketCategoryID, RequestedQuantity
            FROM   WaitlistEntry
            WHERE  WaitlistID = @WaitlistID AND EntryStatus = 'Active'
            ORDER  BY CASE WHEN @AllocationPolicy = 'RANDOM' THEN NEWID() END,
                      CASE WHEN @AllocationPolicy = 'RANDOM' THEN NULL ELSE JoinedTimestamp END,
                      WaitlistEntryID;   -- tie-break xac dinh khi JoinedTimestamp trung

        OPEN cWaitlist;
        FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            -- Dat lai tuong minh truoc moi vong: neu Category khong co dong nao trong
            -- #CategoryState (khong con ghe Available), lenh SELECT duoi day khong gan
            -- gi ca va bien se GIU NGUYEN gia tri cua vong truoc. Khong dua vao ngu
            -- nghia cua DECLARE trong than vong lap.
            DECLARE @Avail INT, @IsBlocked BIT;
            SET @Avail     = NULL;
            SET @IsBlocked = NULL;

            SELECT @Avail = AvailableCount, @IsBlocked = IsBlocked
            FROM   #CategoryState WHERE TicketCategoryID = @CategoryID;

            SET @Avail     = ISNULL(@Avail, 0);      -- khong co dong = 0 ghe kha dung
            SET @IsBlocked = ISNULL(@IsBlocked, 0);

            -- 1. CI07: Category da bi chan boi mot entry dung truoc khong du ghe
            --    -> khong duoc phuc vu entry sau (chong skip-ahead).
            IF @IsBlocked = 1
            BEGIN
                FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
                CONTINUE;
            END

            -- 2. BR42b: all-or-nothing. Khong du cho TOAN BO RequestedQuantity thi
            --    chan Category lai, khong cap tung phan.
            IF @ReqQty > @Avail
            BEGIN
                UPDATE #CategoryState SET IsBlocked = 1 WHERE TicketCategoryID = @CategoryID;
                FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
                CONTINUE;
            END

            -- 3. BR20: khach da du ve thi BO QUA rieng khach nay, KHONG chan Category
            --    (nguoi phia sau van co quyen duoc phuc vu).
            DECLARE @ExistingCount INT;
            SELECT @ExistingCount = TicketCount
            FROM   dbo.fn_GetCustomerTicketCount(@CustomerID, @ConcertID);

            IF (@ExistingCount + @ReqQty) > @PurchaseLimit
            BEGIN
                FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
                CONTINUE;
            END

            -- 4. Gianh ghe THAT SU. UPDLOCK giu den het transaction; READPAST bo qua
            --    ghe dang bi giao dich khac giu -> khong cho, khong deadlock.
            DELETE FROM @AllocatedSeats;

            INSERT INTO @AllocatedSeats (EventSeatID)
            SELECT TOP (@ReqQty) EventSeatID
            FROM   EventSeat WITH (UPDLOCK, READPAST)
            WHERE  ConcertID        = @ConcertID
              AND  TicketCategoryID = @CategoryID
              AND  InventoryStatus  = 'Available';

            IF (SELECT COUNT(*) FROM @AllocatedSeats) = @ReqQty
            BEGIN
                DECLARE @Expiry DATETIME2(7) = DATEADD(SECOND, @OpportunityDuration, @Now);

                -- Thu tu bat buoc: EventSeat truoc, Allocation sau - nguoc lai se vi pham
                -- TRG_InventoryAllocationConsistency (50030).
                UPDATE EventSeat
                SET    InventoryStatus = 'OnHoldForWaitlist'
                WHERE  EventSeatID IN (SELECT EventSeatID FROM @AllocatedSeats);

                UPDATE WaitlistEntry
                SET    EntryStatus                 = 'Granted',
                       OpportunityGrantedTimestamp = @Now,
                       OpportunityExpiryTimestamp  = @Expiry
                WHERE  WaitlistEntryID = @EntryID
                  AND  EntryStatus     = 'Active';   -- BR49a: conditional

                INSERT INTO WaitlistEntryEventSeatAllocation
                    (WaitlistEntryID, EventSeatID, AllocationTimestamp, AllocationStatus)
                SELECT @EntryID, EventSeatID, @Now, 'Active'
                FROM   @AllocatedSeats;

                UPDATE #CategoryState
                SET    AvailableCount = AvailableCount - @ReqQty
                WHERE  TicketCategoryID = @CategoryID;

                DECLARE @SeatIDsCSV NVARCHAR(MAX);
                SELECT @SeatIDsCSV = STRING_AGG(CAST(EventSeatID AS VARCHAR), ',') FROM @AllocatedSeats;

                INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
                VALUES (@SystemUserID, 'SYSTEM_WAITLIST_OPPORTUNITY_GRANTED', 'WaitlistEntry',
                        CAST(@EntryID AS VARCHAR(64)), 'UPDATE', @Now,
                        '{"EntryStatus":"Granted","EventSeatIDs":"' + @SeatIDsCSV + '"}');
            END
            ELSE
            BEGIN
                -- Ton kho thuc te it hon so lieu dinh huong (co giao dich khac vua gianh
                -- mat ghe). Khong co gi da duoc ghi nen khong can hoan tac - chi chan
                -- Category lai va dong bo lai con so.
                UPDATE #CategoryState
                SET    IsBlocked      = 1,
                       AvailableCount = (SELECT COUNT(*) FROM @AllocatedSeats)
                WHERE  TicketCategoryID = @CategoryID;
            END

            FETCH NEXT FROM cWaitlist INTO @EntryID, @CustomerID, @CategoryID, @ReqQty;
        END

        CLOSE cWaitlist;
        DEALLOCATE cWaitlist;
        DROP TABLE #CategoryState;

        COMMIT TRANSACTION;   -- applock 'Transaction' duoc nha tai day

    END TRY
    BEGIN CATCH
        IF CURSOR_STATUS('local', 'cWaitlist') >= 0 CLOSE cWaitlist;
        IF CURSOR_STATUS('local', 'cWaitlist') >= -1 DEALLOCATE cWaitlist;

        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;   -- nha luon applock
        IF OBJECT_ID('tempdb..#CategoryState') IS NOT NULL DROP TABLE #CategoryState;

        THROW;
    END CATCH
END;
GO
