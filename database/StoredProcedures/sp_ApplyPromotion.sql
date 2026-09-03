-- ============================================================
-- sp_ApplyPromotion (BP13 / FR53 / BR35-BR36)
-- Ap dung Promotion vao Booking.
-- Transaction bao gom:
--   1. Kiem tra Promotion con hieu luc.
--   2. Kiem tra DiscountCode hop le (neu yeu cau).
--   3. Kiem tra Usage Limit cua Promotion.
--   4. Tinh DiscountAmount dua tren DiscountType.
--   5. INSERT BookingPromotionApplication.
--   6. Cap nhat Booking.FinalAmount.
--   7. Ghi AuditRecord.
-- ============================================================
CREATE PROCEDURE dbo.sp_ApplyPromotion
(
    @BookingID       INT,
    @PromotionID     INT,
    @DiscountCodeID  INT = NULL,
    @ActorUserID     INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Now DATETIME2(7) = SYSDATETIME();

        -- 1. Kiem tra Booking o trang thai Pending
        DECLARE @BookingStatus  VARCHAR(32);
        DECLARE @SubtotalAmount DECIMAL(18,0);
        DECLARE @FinalAmount    DECIMAL(18,0);
        DECLARE @ConcertID_B    INT;
        DECLARE @CustomerID     INT;

        SELECT @BookingStatus  = BookingStatus,
               @SubtotalAmount = SubtotalAmount,
               @FinalAmount    = FinalAmount,
               @ConcertID_B    = ConcertID,
               @CustomerID     = CustomerUserID
        FROM   Booking WITH (UPDLOCK)
        WHERE  BookingID = @BookingID;

        IF @BookingStatus IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54001, 'sp_ApplyPromotion: BookingID khong ton tai.', 1;
        END

        IF @BookingStatus NOT IN ('Pending')
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54002, 'sp_ApplyPromotion: Chi ap dung Promotion cho Booking dang Pending.', 1;
        END

        -- 2. Kiem tra Promotion
        DECLARE @DiscountType    VARCHAR(32);
        DECLARE @DiscountValue   DECIMAL(18,0);
        DECLARE @StartDatetime   DATETIME2(7);
        DECLARE @EndDatetime     DATETIME2(7);
        DECLARE @PromotionStatus VARCHAR(32);
        DECLARE @UsageLimit      INT;
        DECLARE @CodeRequired    BIT;
        DECLARE @ConcertID_P     INT;
        DECLARE @MaxApplicableQuantity INT;
        DECLARE @MaxDiscountAmount     DECIMAL(18,0);

        SELECT @DiscountType    = DiscountType,
               @DiscountValue   = DiscountValue,
               @StartDatetime   = StartDatetime,
               @EndDatetime     = EndDatetime,
               @PromotionStatus = PromotionStatus,
               @UsageLimit      = UsageLimit,
               @CodeRequired    = CodeRequiredFlag,
               @ConcertID_P     = ConcertID,
               @MaxApplicableQuantity = MaxApplicableQuantity,
               @MaxDiscountAmount     = MaxDiscountAmount
        FROM   Promotion WITH (UPDLOCK) -- CRIT-15: Khoa hang Promotion de ngan race condition
        WHERE  PromotionID = @PromotionID;

        IF @DiscountType IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54003, 'sp_ApplyPromotion: PromotionID khong ton tai.', 1;
        END

        -- Kiem tra Promotion ap dung cho dung Concert
        IF @ConcertID_P <> @ConcertID_B
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54004, 'sp_ApplyPromotion: Promotion khong thuoc Concert cua Booking nay.', 1;
        END

        IF @PromotionStatus <> 'Active'
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54005, 'sp_ApplyPromotion: Promotion khong o trang thai Active.', 1;
        END

        IF @Now < @StartDatetime OR @Now >= @EndDatetime -- Fix I-02: >= thay vi >
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54006, 'sp_ApplyPromotion: Promotion chua hoac da het hieu luc.', 1;
        END

        -- Kiem tra Usage Limit
        IF @UsageLimit IS NOT NULL
        BEGIN
            DECLARE @UsageCount INT;
            -- I-06: Do da lock Promotion, viec dem thuc te tren bang cung duoc an toan hon.
            -- De toi uu nhat phai them cot thong ke vao Promotion, nhung hien tai dem de nguyen voi lock.
            SELECT @UsageCount = COUNT(*)
            FROM   BookingPromotionApplication WITH (READCOMMITTEDLOCK)
            WHERE  PromotionID = @PromotionID;

            IF @UsageCount >= @UsageLimit
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 54007, 'sp_ApplyPromotion: Promotion da dat gioi han su dung.', 1;
            END
        END

        -- Kiem tra ma Discount Code neu yeu cau (FK-03)
        IF @CodeRequired = 1
        BEGIN
            IF @DiscountCodeID IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 54008, 'sp_ApplyPromotion: Promotion yeuCode.', 1;
            END

            -- Lay va lock DiscountCode
            DECLARE @DcStatus VARCHAR(32), @DcFrom DATETIME2(7), @DcTo DATETIME2(7);
            DECLARE @DcGlobalLimit INT, @DcReserved INT, @DcConsumed INT, @DcPerCustomerLimit INT;
            
            SELECT @DcStatus = CodeStatus, @DcFrom = ValidFromDatetime, @DcTo = ValidToDatetime,
                   @DcGlobalLimit = GlobalUsageLimit, @DcReserved = ReservedUsageCount, @DcConsumed = ConsumedUsageCount,
                   @DcPerCustomerLimit = PerCustomerUsageLimit
            FROM   DiscountCode WITH (UPDLOCK)
            WHERE  DiscountCodeID = @DiscountCodeID
              AND  PromotionID = @PromotionID;

            IF @DcStatus IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 54009, 'sp_ApplyPromotion: Discount Code khong ton tai cho Promotion nay.', 1;
            END
            
            IF @DcStatus <> 'Active' OR (@DcFrom IS NOT NULL AND @Now < @DcFrom) OR (@DcTo IS NOT NULL AND @Now >= @DcTo)
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 54009, 'sp_ApplyPromotion: Discount Code khong hop le hoac da het hieu luc.', 1;
            END
            
            -- Kiem tra limit cua DiscountCode (CRIT-15)
            IF @DcGlobalLimit IS NOT NULL AND (@DcReserved + @DcConsumed) >= @DcGlobalLimit
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 54011, 'sp_ApplyPromotion: Discount Code da dat gioi han su dung toan cau.', 1;
            END

            -- CRIT-15: Kiem tra PerCustomerUsageLimit
            IF @DcPerCustomerLimit IS NOT NULL
            BEGIN
                DECLARE @CustomerUsageCount INT;
                SELECT @CustomerUsageCount = COUNT(*)
                FROM BookingPromotionApplication bpa WITH (READCOMMITTEDLOCK)
                JOIN Booking bk ON bk.BookingID = bpa.BookingID
                WHERE bpa.DiscountCodeID = @DiscountCodeID
                  AND bk.CustomerUserID = @CustomerID
                  AND bk.BookingStatus IN ('Pending', 'Confirmed');

                IF @CustomerUsageCount >= @DcPerCustomerLimit
                BEGIN
                    ROLLBACK TRANSACTION;
                    THROW 54012, 'sp_ApplyPromotion: Discount Code da dat gioi han su dung cho khach hang nay.', 1;
                END
            END
        END

        -- Kiem tra Promotion chua duoc ap dung vao Booking nay (BR36a)
        IF EXISTS (
            SELECT 1 FROM BookingPromotionApplication
            WHERE  BookingID = @BookingID AND PromotionID = @PromotionID
        )
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54010, 'sp_ApplyPromotion: Promotion nay da duoc ap dung cho Booking.', 1;
        END

        -- 3. Tinh DiscountAmount dua tren FinalAmount hien tai
        DECLARE @DiscountAmount DECIMAL(18,0);
        DECLARE @DiscountBaseAmount DECIMAL(18,0) = @FinalAmount;

        -- Tinh toan MaxApplicableQuantity (N-03)
        IF @MaxApplicableQuantity IS NOT NULL
        BEGIN
            DECLARE @TotalSeats INT;
            SELECT @TotalSeats = COUNT(*) FROM BookingEventSeatAllocation WHERE BookingID = @BookingID AND AllocationStatus = 'Active';
            
            IF @TotalSeats > @MaxApplicableQuantity AND @TotalSeats > 0
            BEGIN
                -- Binh quan gia tri DiscountBaseAmount theo so luong ghe cho phep
                SET @DiscountBaseAmount = CAST(@FinalAmount * CAST(@MaxApplicableQuantity AS DECIMAL(18,4)) / CAST(@TotalSeats AS DECIMAL(18,4)) AS DECIMAL(18,0));
            END
        END

        -- Chuan hoa DiscountType (data co the luu dang legacy 'PERCENTAGE'/'FIXED')
        SET @DiscountType = CASE
            WHEN UPPER(@DiscountType) IN ('PERCENTAGE', 'PERCENT')       THEN 'Percentage'
            WHEN UPPER(@DiscountType) IN ('FIXED', 'FIXED AMOUNT')      THEN 'Fixed Amount'
            ELSE @DiscountType
        END;

        IF @DiscountType = 'Percentage'
            -- BR36d: Tinh discount tren "running hien tai" (sau khi da gioi han MaxApplicableQuantity)
            SET @DiscountAmount = CAST(@DiscountBaseAmount * @DiscountValue / 100 AS DECIMAL(18,0));
        ELSE IF @DiscountType = 'Fixed Amount'
            SET @DiscountAmount = @DiscountValue;
        ELSE
            SET @DiscountAmount = 0;

        -- Dam bao discount khong lon hon FinalAmount hien tai (BR36e)
        IF @DiscountAmount > @FinalAmount SET @DiscountAmount = @FinalAmount;

        -- Ap dung MaxDiscountAmount (N-03)
        IF @MaxDiscountAmount IS NOT NULL AND @DiscountAmount > @MaxDiscountAmount
        BEGIN
            SET @DiscountAmount = @MaxDiscountAmount;
        END

        -- 4. INSERT BookingPromotionApplication
        -- Xac dinh ApplicationOrder
        DECLARE @NextOrder INT = ISNULL((SELECT MAX(ApplicationOrder) FROM BookingPromotionApplication WITH (UPDLOCK) WHERE BookingID = @BookingID), 0) + 1;

        INSERT INTO BookingPromotionApplication
            (BookingID, PromotionID, DiscountCodeID, ApplicationOrder, DiscountAmount, AppliedTimestamp)
        VALUES
            (@BookingID, @PromotionID, @DiscountCodeID, @NextOrder, @DiscountAmount, @Now);

        -- Cap nhat current usage count cho DiscountCode neu co (CRIT-02)
        IF @DiscountCodeID IS NOT NULL
        BEGIN
            UPDATE DiscountCode
            SET ReservedUsageCount = ReservedUsageCount + 1
            WHERE DiscountCodeID = @DiscountCodeID;
        END

        -- 5. Cap nhat Booking.FinalAmount bang Inline TVF
        UPDATE b
        SET    b.FinalAmount = fa.FinalAmount
        FROM   Booking b
        CROSS APPLY dbo.fn_CalculateFinalAmount(b.BookingID) fa
        WHERE  b.BookingID = @BookingID;

        -- 6. Ghi AuditRecord
        INSERT INTO AuditRecord
            (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES
            (@ActorUserID, 'PROMOTION_APPLIED', 'Booking',
             CAST(@BookingID AS VARCHAR(64)), 'UPDATE',
             @Now,
             '{"PromotionID":' + CAST(@PromotionID AS VARCHAR) + ',"DiscountAmount":' + CAST(@DiscountAmount AS VARCHAR) + '}');

        COMMIT TRANSACTION;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
