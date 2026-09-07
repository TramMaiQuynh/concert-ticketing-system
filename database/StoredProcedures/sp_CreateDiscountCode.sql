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