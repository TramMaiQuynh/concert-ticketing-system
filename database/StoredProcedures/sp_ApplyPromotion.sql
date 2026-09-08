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
        DECLARE @ConcertID_B    INT;
        DECLARE @CustomerID     INT;

        -- UPDLOCK giu hang Booking den het transaction. Khong doc san Final/Subtotal
        -- Amount o day: buoc 4 tinh lai ca chuoi tu Allocation nen moi con so doc
        -- truoc deu se lac hau ngay trong chinh transaction nay.
        SELECT @BookingStatus  = BookingStatus,
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

        -- 1b. Khong duoc doi gia don hang khi da co mot giao dich thanh toan DANG CHO.
        --
        -- sp_InitiatePayment chup lai Booking.FinalAmount vao Payment.Amount tai thoi
        -- diem khoi tao. Neu sau do Promotion lam FinalAmount thay doi, khoan tien khach
        -- dang tra o cong thanh toan khong con khop voi don hang nua - va khi cong bao
        -- thu tien thanh cong thi he thong buoc phai hoan lai roi bat khach tra lai tu
        -- dau. Do la trai nghiem hong va la duong sinh ra tien treo.
        --
        -- Quy tac dung theo nghiep vu thuc te: mot khi khach da buoc vao cong thanh toan,
        -- tong tien cua don bi KHOA. Muon doi khuyen mai thi phai huy lan thanh toan do
        -- truoc (sp_FailPayment), roi khoi tao lai - luc do Payment.Amount duoc chup lai
        -- theo gia moi.
        --
        -- UPDLOCK, HOLDLOCK giu range lock tren cac Payment cua Booking nay den het
        -- transaction, doi xung voi chinh cach sp_InitiatePayment kiem tra. Nho do hai
        -- luong "ap khuyen mai" va "khoi tao thanh toan" chay dong thoi khong the cung
        -- di qua: thu tu lay khoa cua ca hai SP deu la Booking -> Payment nen khong sinh
        -- deadlock moi.
        IF EXISTS (
            SELECT 1
            FROM   Payment WITH (UPDLOCK, HOLDLOCK)
            WHERE  BookingID     = @BookingID
              AND  PaymentStatus = 'Pending'
        )
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54013, 'sp_ApplyPromotion: Booking dang co giao dich thanh toan cho xu ly. Huy giao dich do truoc khi thay doi khuyen mai.', 1;
        END

        -- 2. Kiem tra Promotion
        -- Chi doc nhung thuoc tinh dung cho viec KIEM TRA DIEU KIEN ap dung. Cac tham
        -- so dung de TINH TIEN (DiscountType/DiscountValue/MaxApplicableQuantity/
        -- MaxDiscountAmount) do buoc 4 doc, vi buoc do tinh cho ca chuoi chu khong
        -- rieng Promotion nay.
        DECLARE @DiscountType    VARCHAR(32);
        DECLARE @StartDatetime   DATETIME2(7);
        DECLARE @EndDatetime     DATETIME2(7);
        DECLARE @PromotionStatus VARCHAR(32);
        DECLARE @UsageLimit      INT;
        DECLARE @CodeRequired    BIT;
        DECLARE @ConcertID_P     INT;

        SELECT @DiscountType    = DiscountType,
               @StartDatetime   = StartDatetime,
               @EndDatetime     = EndDatetime,
               @PromotionStatus = PromotionStatus,
               @UsageLimit      = UsageLimit,
               @CodeRequired    = CodeRequiredFlag,
               @ConcertID_P     = ConcertID
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
        --
        -- QUY TAC DEM (dung chung cho ca han muc Promotion o day va han muc theo khach
        -- hang cua DiscountCode ben duoi) - mot luot duoc tinh la DA DUNG khi:
        --   * Booking dang Pending          -> dang giu cho, phai tinh de hai don dong
        --                                      thoi khong cung vuot han muc;
        --   * Booking Confirmed             -> da thanh don;
        --   * Booking Cancelled NHUNG da tung Confirmed (ConfirmedTimestamp IS NOT NULL)
        --                                   -> da thanh don roi moi huy: van tinh, de
        --                                      khong the lap vong dat-huy nham xai lai
        --                                      khuyen mai vo han.
        -- KHONG tinh:
        --   * Booking Expired               -> khach khong bao gio tra tien;
        --   * Booking Cancelled tu Pending  -> huy truoc khi thanh don.
        -- Truoc day cau lenh nay dem TAT CA BookingPromotionApplication bat ke trang thai
        -- Booking, nen mot chuong trinh UsageLimit=100 bi dot het han muc boi nhung don
        -- het han khong ai tra tien - chuong trinh chet yeu du chua ban duoc gi.
        --
        -- Ghi chu: dieu kien "Cancelled va tung Confirmed" chi bieu dien duoc nho
        -- ConfirmedTimestamp duoc GIU LAI qua chuyen doi Confirmed -> Cancelled
        -- (CHK_Booking_TimestampCoherence, §21 R11). Quy tac nay dong bo voi vong doi
        -- Reserved/Consumed cua DiscountCode trong TRG_Booking_DiscountUsageGuard.
        IF @UsageLimit IS NOT NULL
        BEGIN
            DECLARE @UsageCount INT;
            -- I-06: Promotion da bi lock o tren nen phep dem tai cho la an toan.
            SELECT @UsageCount = COUNT(*)
            FROM   BookingPromotionApplication bpa WITH (READCOMMITTEDLOCK)
            JOIN   Booking bk ON bk.BookingID = bpa.BookingID
            WHERE  bpa.PromotionID = @PromotionID
              AND  (    bk.BookingStatus IN ('Pending', 'Confirmed')
                     OR (bk.BookingStatus = 'Cancelled' AND bk.ConfirmedTimestamp IS NOT NULL));

            IF @UsageCount >= @UsageLimit
            BEGIN
                ROLLBACK TRANSACTION;
                THROW 54007, 'sp_ApplyPromotion: Promotion da dat gioi han su dung.', 1;
            END
        END

        -- FK-03: Promotion yeu cau code thi bat buoc phai co code.
        IF @CodeRequired = 1 AND @DiscountCodeID IS NULL
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 54008, 'sp_ApplyPromotion: Promotion nay bat buoc phai co Discount Code.', 1;
        END

        -- Kiem tra Discount Code MOI KHI co code duoc truyen vao - khong phu thuoc
        -- CodeRequiredFlag.
        -- Truoc day toan bo khoi nay nam trong `IF @CodeRequired = 1`, nen voi mot
        -- Promotion khong bat buoc code ma caller van gui @DiscountCodeID thi:
        -- GlobalUsageLimit va PerCustomerUsageLimit deu KHONG duoc kiem tra, trong khi
        -- ReservedUsageCount o cuoi SP van tang. Han muc theo khach hang khi do bi bo
        -- qua hoan toan, con han muc toan cuc chi bi chan muon boi CHECK constraint
        -- duoi dang loi rang buoc tho thay vi 54011.
        IF @DiscountCodeID IS NOT NULL
        BEGIN
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
                -- Cung quy tac dem voi han muc Promotion o tren: loai Booking Expired
                -- va Booking bi huy khi CHUA tung Confirmed. Truoc day dieu kien la
                -- IN ('Pending','Confirmed','Cancelled') - vua bo sot Expired vua tinh
                -- ca nhung don huy khi chua thanh don, tuc hai sai lech nguoc chieu nhau.
                SELECT @CustomerUsageCount = COUNT(*)
                FROM BookingPromotionApplication bpa WITH (READCOMMITTEDLOCK)
                JOIN Booking bk ON bk.BookingID = bpa.BookingID
                WHERE bpa.DiscountCodeID = @DiscountCodeID
                  AND bk.CustomerUserID = @CustomerID
                  AND (    bk.BookingStatus IN ('Pending', 'Confirmed')
                        OR (bk.BookingStatus = 'Cancelled' AND bk.ConfirmedTimestamp IS NOT NULL));

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

        -- 3. Ghi nhan viec ap dung Promotion nay vao chuoi cua Booking.
        --
        -- ApplicationOrder va DiscountAmount la GIA TRI DAN XUAT, khong phai du lieu
        -- nhap: BR36d/PI06 quy dinh thu tu ap dung la thu tu TAO Promotion tang dan,
        -- khong phai thu tu khach bam. Ca hai duoc buoc 4 tinh lai, nen o day chi ghi
        -- gia tri tam de thoa NOT NULL va CHK_BPA_DiscountAmount >= 0.
        DECLARE @DiscountAmount DECIMAL(18,0);

        INSERT INTO BookingPromotionApplication
            (BookingID, PromotionID, DiscountCodeID, ApplicationOrder, DiscountAmount, AppliedTimestamp)
        VALUES
            (@BookingID, @PromotionID, @DiscountCodeID, 0, 0, @Now);

        -- Cap nhat current usage count cho DiscountCode neu co (CRIT-02)
        IF @DiscountCodeID IS NOT NULL
        BEGIN
            UPDATE DiscountCode
            SET ReservedUsageCount = ReservedUsageCount + 1
            WHERE DiscountCodeID = @DiscountCodeID;
        END

        -- 4. Tinh lai TOAN BO chuoi Promotion cua Booking theo thu tu chuan tac.
        --
        -- VI SAO PHAI TINH LAI CA CHUOI, khong cong don duoc:
        -- BR36d/PI06 quy dinh thu tu ap dung la thu tu TAO Promotion tang dan. Khach
        -- lai co the ap dung mot Promotion tao TRUOC vao SAU. Khi do Promotion vua
        -- them chen vao GIUA chuoi, va moi Promotion dung sau no phai tinh lai tren
        -- mot phan con lai khac. Cong don theo thu tu bam se cho ket qua phu thuoc
        -- thao tac nguoi dung: cung mot gio hang, cung hai Promotion, bam khac thu tu
        -- ra hai so tien khac nhau (Fixed truoc roi Percentage khong bang Percentage
        -- truoc roi Fixed). Do la thu BR36d ton tai de ngan.
        --
        -- KHOA THU TU: R21 khong khai bao cot thoi diem tao cho Promotion, trong khi
        -- BR36d/PI06/§12.16.3 lai sap theo Promotion.CreatedTimestamp. PromotionID la
        -- IDENTITY, tang don dieu theo thu tu tao va khong bao giu trung, nen no la
        -- hien thuc trung thuc cua "thu tu tao" ma khong can them cot moi - dong thoi
        -- tranh bai toan trung moc thoi gian phai lay ID ra phan giai.
        --
        -- Khong lay UPDLOCK tren cac Promotion khac trong chuoi: he thong khong co
        -- duong ghi nao sua DiscountType/DiscountValue/MaxDiscountAmount sau khi tao
        -- (chi co sp_CreatePromotion va sp_UpdatePromotionStatus), nen cac tham so
        -- dung de tinh la bat bien - khoa them chi mo rong be mat deadlock.

        -- 4a. Danh so lai ApplicationOrder theo dung thu tu chuan tac.
        --     Mot lenh set-based duy nhat: khong co trang thai trung gian nao de lo.
        ;WITH ChuoiKhuyenMai AS (
            SELECT ApplicationOrder,
                   ThuTuChuan = ROW_NUMBER() OVER (ORDER BY PromotionID)
            FROM   BookingPromotionApplication
            WHERE  BookingID = @BookingID
        )
        UPDATE ChuoiKhuyenMai SET ApplicationOrder = ThuTuChuan;

        -- 4b. Chay tuan tu tren PHAN CON LAI, dung nguyen bo quy tac cu cho tung buoc.
        DECLARE @ConLai DECIMAL(18,0);
        SELECT @ConLai = Subtotal FROM dbo.fn_CalculateBookingSubtotal(@BookingID);

        DECLARE @TotalSeats INT =
            (SELECT COUNT(*) FROM BookingEventSeatAllocation
             WHERE  BookingID = @BookingID AND AllocationStatus = 'Active');

        DECLARE @Buoc      INT = 1;
        DECLARE @SoBuoc    INT =
            (SELECT COUNT(*) FROM BookingPromotionApplication WHERE BookingID = @BookingID);

        DECLARE @bType   VARCHAR(32);
        DECLARE @bValue  DECIMAL(18,0);
        DECLARE @bMaxQty INT;
        DECLARE @bMaxAmt DECIMAL(18,0);
        DECLARE @bBase   DECIMAL(18,0);
        DECLARE @bGiam   DECIMAL(18,0);

        WHILE @Buoc <= @SoBuoc
        BEGIN
            SELECT @bType   = p.DiscountType,
                   @bValue  = p.DiscountValue,
                   @bMaxQty = p.MaxApplicableQuantity,
                   @bMaxAmt = p.MaxDiscountAmount
            FROM   BookingPromotionApplication bpa
            JOIN   Promotion p ON p.PromotionID = bpa.PromotionID
            WHERE  bpa.BookingID = @BookingID AND bpa.ApplicationOrder = @Buoc;

            -- Base cua buoc nay la phan con lai (BR36d), sau khi gioi han theo
            -- MaxApplicableQuantity (N-03).
            SET @bBase = @ConLai;
            IF @bMaxQty IS NOT NULL AND @TotalSeats > @bMaxQty AND @TotalSeats > 0
                SET @bBase = CAST(@ConLai * CAST(@bMaxQty AS DECIMAL(18,4))
                                          / CAST(@TotalSeats AS DECIMAL(18,4)) AS DECIMAL(18,0));

            -- Khong can chuan hoa @bType: CHK_Promotion_DiscountType chi cho phep hai
            -- gia tri nay ton tai trong bang; chuan hoa dau vao lam mot lan duy nhat
            -- tai sp_CreatePromotion.
            IF @bType = 'Percentage'
                -- CAST ve DECIMAL(18,0) = lam tron VND ngay sau buoc nay (BR36e/A19),
                -- khong don lam tron ve cuoi chuoi.
                SET @bGiam = CAST(@bBase * @bValue / 100 AS DECIMAL(18,0));
            ELSE IF @bType = 'Fixed Amount'
                SET @bGiam = @bValue;
            ELSE
                SET @bGiam = 0;

            -- Cap dung bang phan con lai truoc (BR36e: payable ve 0, khong am), roi
            -- moi ap MaxDiscountAmount (N-03) - giu nguyen thu tu hai chot nhu cu.
            IF @bGiam > @ConLai SET @bGiam = @ConLai;
            IF @bMaxAmt IS NOT NULL AND @bGiam > @bMaxAmt SET @bGiam = @bMaxAmt;

            UPDATE BookingPromotionApplication
            SET    DiscountAmount = @bGiam
            WHERE  BookingID = @BookingID AND ApplicationOrder = @Buoc;

            SET @ConLai = @ConLai - @bGiam;
            SET @Buoc   = @Buoc + 1;
        END

        -- Muc giam THUC TE cua Promotion vua ap dung, doc lai sau khi ca chuoi da
        -- on dinh - dung cho AuditRecord o buoc 6.
        SELECT @DiscountAmount = DiscountAmount
        FROM   BookingPromotionApplication
        WHERE  BookingID = @BookingID AND PromotionID = @PromotionID;

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
