-- ============================================================
-- sp_CreateConcert (BP1 / FR01-FR03)
-- Tao Concert moi o trang thai Draft (BP1, §23.5: "tao Concert
-- o trang thai Draft").
-- Kiem tra (DR-01, BR01, FR01-03, BR54):
--   - @OrganizerUserID phai la User DANG GIU Role 'Organizer' Active
--     (Organizer khong phai entity rieng; Concert.OrganizerUserID tham
--     chieu User Account + User-Role Assignment - §13 Note Design).
--   - Artist/Venue ton tai.
--   - EndDatetime > StartDatetime; PurchaseLimit > 0.
--   - Neu co SaleStart/SaleEnd -> phai hop le (SaleEnd >= SaleStart).
-- Ghi AuditRecord.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateConcert
(
    @OrganizerUserID INT,
    @ArtistID        INT,
    @VenueID         INT,
    @ConcertName     NVARCHAR(255),
    @StartDatetime   DATETIME2(7),
    @EndDatetime     DATETIME2(7),
    @SaleStartDatetime   DATETIME2(7),
    @SaleEndDatetime     DATETIME2(7),
    @PurchaseLimit       INT = 4,
    @TemporaryHoldDuration INT,
    @FairAccessEnabled BIT = 0,
    @WaitlistEnabled   BIT = 0,
    @SalesPaused       BIT = 0,
    @CancellationPolicy NVARCHAR(500),
    @RefundPolicy       NVARCHAR(500),
    @NewConcertID       INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Concert chi duoc tao o trang thai Draft (BP1/§23.5)
        --    Khi can chuyen trang thai: dung sp_UpdateConcertStatus.
        DECLARE @ConcertStatus VARCHAR(32) = 'Draft';

        -- 2. Kiem tra dates
        IF @EndDatetime <= @StartDatetime
            THROW 58002, 'sp_CreateConcert: EndDatetime phai sau StartDatetime.', 1;

        IF @PurchaseLimit <= 0
            THROW 58003, 'sp_CreateConcert: PurchaseLimit phai lon hon 0.', 1;

        -- Sale dates hop le (neu co cau hinh)
        IF @SaleStartDatetime IS NOT NULL AND @SaleEndDatetime IS NOT NULL
           AND @SaleEndDatetime < @SaleStartDatetime
            THROW 58007, 'sp_CreateConcert: SaleEndDatetime phai >= SaleStartDatetime.', 1;

        -- 3. Kiem tra references
        IF NOT EXISTS (SELECT 1 FROM Artist WHERE ArtistID = @ArtistID)
            THROW 58004, 'sp_CreateConcert: Artist khong ton tai.', 1;
        IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID = @VenueID)
            THROW 58005, 'sp_CreateConcert: Venue khong ton tai.', 1;

        -- 3b. DR-01 / BR01: Organizer phai la User dang giu Role 'Organizer' Active
        --     (khong chi can tai khoan Active). RBAC §23.7.
        IF NOT EXISTS (
            SELECT 1
            FROM   UserAccount ua
            JOIN   UserRoleAssignment ura ON ura.UserID = ua.UserID AND ura.AssignmentStatus = 'Active'
            JOIN   Role r ON r.RoleID = ura.RoleID AND r.RoleName = 'Organizer' AND r.RoleStatus = 'Active'
            WHERE  ua.UserID = @OrganizerUserID AND ua.AccountStatus = 'Active'
        )
            THROW 58006, 'sp_CreateConcert: Organizer khong ton tai, khong Active, hoac khong giu Role Organizer.', 1;

        -- 4. Insert
        INSERT INTO Concert
            (OrganizerUserID, ArtistID, VenueID, ConcertName, StartDatetime, EndDatetime,
             ConcertStatus, SaleStartDatetime, SaleEndDatetime, PurchaseLimit, TemporaryHoldDuration,
             FairAccessEnabled, WaitlistEnabled, SalesPaused, CancellationPolicy, RefundPolicy)
        VALUES
            (@OrganizerUserID, @ArtistID, @VenueID, @ConcertName, @StartDatetime, @EndDatetime,
             @ConcertStatus, @SaleStartDatetime, @SaleEndDatetime, @PurchaseLimit, @TemporaryHoldDuration,
             @FairAccessEnabled, @WaitlistEnabled, @SalesPaused, @CancellationPolicy, @RefundPolicy);

        SET @NewConcertID = SCOPE_IDENTITY();

        -- 5. Audit
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@OrganizerUserID, 'CONCERT_CREATED', 'Concert',
                CAST(@NewConcertID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"ConcertStatus":"Draft"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO