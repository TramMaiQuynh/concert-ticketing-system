-- ============================================================
-- sp_CreatePromotion (BP13 / FR52)
-- Tao Promotion cho Concert. Chi Organizer cua Concert hoac Admin.
-- Kiem tra: EndDatetime > StartDatetime; DiscountValue > 0.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreatePromotion
(
    @ActorUserID    INT,
    @ConcertID      INT,
    @PromotionName  NVARCHAR(255),
    @PromotionDescription NVARCHAR(500),
    @DiscountType   VARCHAR(32),
    @DiscountValue  DECIMAL(18,0),
    @StartDatetime  DATETIME2(7),
    @EndDatetime    DATETIME2(7),
    @UsageLimit     INT,
    @CodeRequiredFlag BIT,
    @NewPromotionID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT;
        SELECT @OrganizerUserID = OrganizerUserID FROM Concert WHERE ConcertID = @ConcertID;

        IF @OrganizerUserID IS NULL
            THROW 58301, 'sp_CreatePromotion: Concert khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 58302, 'sp_CreatePromotion: Actor khong co quyen.', 1;

        IF @DiscountType NOT IN ('PERCENTAGE', 'FIXED')
            THROW 58303, 'sp_CreatePromotion: DiscountType phai la PERCENTAGE hoac FIXED.', 1;

        IF @DiscountValue <= 0
            THROW 58304, 'sp_CreatePromotion: DiscountValue phai lon hon 0.', 1;

        IF @EndDatetime <= @StartDatetime
            THROW 58305, 'sp_CreatePromotion: EndDatetime phai sau StartDatetime.', 1;

        IF @CodeRequiredFlag = 1 AND ISNULL(@PromotionName, '') = ''
            THROW 58306, 'sp_CreatePromotion: PromotionName khong duoc de trong khi yeu cau code.', 1;

        INSERT INTO Promotion
            (ConcertID, PromotionName, PromotionDescription, DiscountType, DiscountValue,
             StartDatetime, EndDatetime, PromotionStatus, UsageLimit, CodeRequiredFlag)
        VALUES
            (@ConcertID, @PromotionName, @PromotionDescription, @DiscountType, @DiscountValue,
             @StartDatetime, @EndDatetime, 'Active', @UsageLimit, @CodeRequiredFlag);

        SET @NewPromotionID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'PROMOTION_CREATED', 'Promotion',
                CAST(@NewPromotionID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"PromotionName":"' + ISNULL(@PromotionName,'') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO