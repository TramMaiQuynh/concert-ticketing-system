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
CREATE OR ALTER PROCEDURE dbo.sp_ApplyPromotion
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

        SELECT @BookingStatus  = BookingStatus,
               @SubtotalAmount = SubtotalAmount,
               @FinalAmount    = FinalAmount,
               @ConcertID_B   = ConcertID
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

        SELECT @DiscountType    = DiscountType,
               @DiscountValue   = DiscountValue,
               @StartDatetime   = StartDatetime,
               @EndDatetime     = EndDatetime,
               @PromotionStatus = PromotionStatus,
               @UsageLimit      = UsageLimit,
               @CodeRequired    = CodeRequiredFlag,
               @ConcertID_P     = ConcertID
        FROM   Promotion
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

        IF @Now < @StartDatetime OR @Now > @EndDatetime
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54006, 'sp_ApplyPromotion: Promotion chua hoac da het hieu luc.', 1;
        END

        -- Kiem tra Usage Limit
        IF @UsageLimit IS NOT NULL
        BEGIN
            DECLARE @UsageCount INT;
            SELECT @UsageCount = COUNT(*)
            FROM   BookingPromotionApplication
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
                THROW 54008, 'sp_ApplyPromotion: Promotion yeu cau Discount Code.', 1;
            END

            IF NOT EXISTS (
                SELECT 1 FROM DiscountCode
                WHERE  DiscountCodeID = @DiscountCodeID
                  AND  PromotionID    = @PromotionID
                  AND  CodeStatus     = 'Active'
            )
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 54009, 'sp_ApplyPromotion: Discount Code khong hop le hoac da het hieu luc.', 1;
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

        -- 3. Tinh DiscountAmount
        DECLARE @DiscountAmount DECIMAL(18,0);

        IF @DiscountType = 'PERCENTAGE'
            SET @DiscountAmount = CAST(@SubtotalAmount * @DiscountValue / 100 AS DECIMAL(18,0));
        ELSE IF @DiscountType = 'FIXED'
            SET @DiscountAmount = @DiscountValue;
        ELSE
            SET @DiscountAmount = 0;

        -- Dam bao discount khong lon hon FinalAmount hien tai
        IF @DiscountAmount > @FinalAmount SET @DiscountAmount = @FinalAmount;

        -- 4. INSERT BookingPromotionApplication
        INSERT INTO BookingPromotionApplication
            (BookingID, PromotionID, DiscountCodeID, DiscountAmount, AppliedTimestamp)
        VALUES
            (@BookingID, @PromotionID, @DiscountCodeID, @DiscountAmount, @Now);

        -- 5. Cap nhat Booking.FinalAmount
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
