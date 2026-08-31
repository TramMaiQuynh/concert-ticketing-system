-- ============================================================
-- sp_UpdateConcert (BP1 / FR02, FR03)
-- Cap nhat thong tin Concert. Chi cho phep khi Concert o
-- trang thai Draft hoac Published (chua mo ban).
-- Kiem tra quyen so huu: @ActorUserID phai la Organizer cua Concert
-- hoac la Admin (co Role Admin - kiem tra qua UserRoleAssignment).
-- Ghi AuditRecord voi PreviousValue/NewValue.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateConcert
(
    @ConcertID         INT,
    @ActorUserID       INT,
    @ConcertName       NVARCHAR(255) = NULL,
    @ArtistID          INT = NULL,
    @VenueID           INT = NULL,
    @StartDatetime     DATETIME2(7) = NULL,
    @EndDatetime       DATETIME2(7) = NULL,
    @SaleStartDatetime DATETIME2(7) = NULL,
    @SaleEndDatetime   DATETIME2(7) = NULL,
    @PurchaseLimit     INT = NULL,
    @TemporaryHoldDuration INT = NULL,
    @FairAccessEnabled BIT = NULL,
    @WaitlistEnabled   BIT = NULL,
    @SalesPaused       BIT = NULL,
    @CancellationPolicy NVARCHAR(500) = NULL,
    @RefundPolicy      NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @CurrentStatus VARCHAR(32), @OrganizerUserID INT;

        SELECT @CurrentStatus = ConcertStatus, @OrganizerUserID = OrganizerUserID
        FROM Concert WHERE ConcertID = @ConcertID;

        IF @CurrentStatus IS NULL
            THROW 58010, 'sp_UpdateConcert: Concert khong ton tai.', 1;

        -- Chi cho phep sua khi Draft/Published (BR49)
        IF @CurrentStatus NOT IN ('Draft', 'Published')
            THROW 58011, 'sp_UpdateConcert: Chi sua duoc Concert o trang thai Draft hoac Published.', 1;

        -- Quyen: Organizer cua Concert hoac Admin
        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 58012, 'sp_UpdateConcert: Actor khong co quyen cap nhat Concert nay.', 1;

        IF @EndDatetime IS NOT NULL AND @StartDatetime IS NOT NULL AND @EndDatetime <= @StartDatetime
            THROW 58013, 'sp_UpdateConcert: EndDatetime phai sau StartDatetime.', 1;

        -- Luu gia tri cu de ghi audit
        DECLARE @OldName NVARCHAR(255) = (SELECT ConcertName FROM Concert WHERE ConcertID = @ConcertID);

        UPDATE Concert
        SET ConcertName         = COALESCE(@ConcertName, ConcertName),
            ArtistID            = COALESCE(@ArtistID, ArtistID),
            VenueID             = COALESCE(@VenueID, VenueID),
            StartDatetime       = COALESCE(@StartDatetime, StartDatetime),
            EndDatetime         = COALESCE(@EndDatetime, EndDatetime),
            SaleStartDatetime   = COALESCE(@SaleStartDatetime, SaleStartDatetime),
            SaleEndDatetime     = COALESCE(@SaleEndDatetime, SaleEndDatetime),
            PurchaseLimit       = COALESCE(@PurchaseLimit, PurchaseLimit),
            TemporaryHoldDuration = COALESCE(@TemporaryHoldDuration, TemporaryHoldDuration),
            FairAccessEnabled   = COALESCE(@FairAccessEnabled, FairAccessEnabled),
            WaitlistEnabled     = COALESCE(@WaitlistEnabled, WaitlistEnabled),
            SalesPaused         = COALESCE(@SalesPaused, SalesPaused),
            CancellationPolicy  = COALESCE(@CancellationPolicy, CancellationPolicy),
            RefundPolicy        = COALESCE(@RefundPolicy, RefundPolicy)
        WHERE ConcertID = @ConcertID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'CONCERT_UPDATED', 'Concert',
                CAST(@ConcertID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"ConcertName":"' + @OldName + '"}',
                '{"ConcertName":"' + ISNULL(@ConcertName, @OldName) + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO