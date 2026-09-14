-- ============================================================
-- sp_CreateDiscountCode (BP13 / FR52)
-- Tao Discount Code cho Promotion. Chi Organizer cua Concert hoac Admin.
-- Code Value duy nhat trong pham vi Promotion (UNIQUE(PromotionID,CodeValue)).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateDiscountCode
(
    @ActorUserID INT,
    @PromotionID INT,
    @CodeValue   VARCHAR(64),
    @ValidFromDatetime DATETIME2(7),
    @ValidToDatetime   DATETIME2(7),
    @GlobalUsageLimit  INT = NULL,
    @PerCustomerUsageLimit INT = NULL,
    @NewDiscountCodeID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Quyen: Organizer cua Concert cua Promotion hoac Admin
        IF NOT EXISTS (
            SELECT 1
            FROM Promotion p
            JOIN Concert c ON c.ConcertID = p.ConcertID
            WHERE p.PromotionID = @PromotionID
              AND (
                    c.OrganizerUserID = @ActorUserID
                    OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                               JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                               WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
                  )
        )
            THROW 58601, 'sp_CreateDiscountCode: Actor khong co quyen voi Promotion nay.', 1;

        IF ISNULL(@CodeValue, '') = ''
            THROW 58602, 'sp_CreateDiscountCode: CodeValue khong duoc de trong.', 1;

        IF @ValidToDatetime IS NOT NULL AND @ValidFromDatetime IS NOT NULL AND @ValidToDatetime < @ValidFromDatetime
            THROW 58603, 'sp_CreateDiscountCode: ValidToDatetime phai >= ValidFromDatetime.', 1;

        -- Ma phai xac dinh DUY NHAT mot Promotion trong pham vi CONCERT.
        -- UNIQUE(PromotionID, CodeValue) chi bao dam duy nhat trong mot Promotion, nen
        -- hai Promotion Active cua CUNG mot Concert van cung dat duoc ma 'X'. Khach go
        -- 'X' khi dat ve thi he thong khong con cach nao biet ho dinh dung uu dai nao —
        -- va do khong phai tinh huong gia dinh: BookingRepository tra cuu ma bang mot
        -- cau SELECT ky vong toi da mot dong, gap hai dong la loi 500 chu khong phai
        -- mot thong bao hieu duoc. Chan su nhap nhang ngay tai noi no duoc sinh ra.
        IF EXISTS (
            SELECT 1
            FROM   DiscountCode dc
            JOIN   Promotion    p2 ON p2.PromotionID = dc.PromotionID
            WHERE  dc.CodeValue       = @CodeValue
              AND  dc.CodeStatus      = 'Active'
              AND  p2.PromotionStatus = 'Active'
              AND  p2.PromotionID    <> @PromotionID
              AND  p2.ConcertID       = (SELECT ConcertID FROM Promotion WHERE PromotionID = @PromotionID)
        )
            THROW 58604, 'sp_CreateDiscountCode: Ma nay da duoc mot Promotion Active khac cua cung Concert su dung.', 1;

        INSERT INTO DiscountCode (PromotionID, CodeValue, ValidFromDatetime, ValidToDatetime, CodeStatus, GlobalUsageLimit, PerCustomerUsageLimit)
        VALUES (@PromotionID, @CodeValue, @ValidFromDatetime, @ValidToDatetime, 'Active', @GlobalUsageLimit, @PerCustomerUsageLimit);

        SET @NewDiscountCodeID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'DISCOUNT_CODE_CREATED', 'DiscountCode',
                CAST(@NewDiscountCodeID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"CodeValue":"' + STRING_ESCAPE(@CodeValue, 'json') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO