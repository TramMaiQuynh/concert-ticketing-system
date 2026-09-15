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
    @ArtistIDs         NVARCHAR(MAX) = NULL,
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
    @RefundPolicy      NVARCHAR(500) = NULL,
    @CancellationDeadlineHours INT = NULL,
    @RefundPercentage  DECIMAL(5,2) = NULL
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
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 58012, 'sp_UpdateConcert: Actor khong co quyen cap nhat Concert nay.', 1;

        IF @EndDatetime IS NOT NULL AND @StartDatetime IS NOT NULL AND @EndDatetime <= @StartDatetime
            THROW 58013, 'sp_UpdateConcert: EndDatetime phai sau StartDatetime.', 1;

        -- Neu caller gui ArtistIDs, thay toan bo danh sach trong cung transaction.
        -- NULL co nghia giu nguyen; [] va phan tu trung/lap sai deu bi tu choi.
        IF @ArtistIDs IS NOT NULL
        BEGIN
            IF ISJSON(@ArtistIDs) <> 1
                THROW 58025, 'sp_UpdateConcert: ArtistIDs phai la JSON array khong rong, khong trung lap.', 1;

            DECLARE @ParsedArtists TABLE
            (
                ArtistID INT NULL,
                ArtistOrder INT NOT NULL
            );
            INSERT INTO @ParsedArtists (ArtistID, ArtistOrder)
            SELECT TRY_CONVERT(INT, [value]), TRY_CONVERT(INT, [key]) + 1
            FROM OPENJSON(@ArtistIDs);

            IF NOT EXISTS (SELECT 1 FROM @ParsedArtists)
               OR EXISTS (SELECT 1 FROM @ParsedArtists WHERE ArtistID IS NULL OR ArtistID <= 0)
               OR EXISTS (SELECT ArtistID FROM @ParsedArtists GROUP BY ArtistID HAVING COUNT(*) > 1)
                THROW 58025, 'sp_UpdateConcert: ArtistIDs phai la JSON array khong rong, khong trung lap.', 1;

            DECLARE @Artists TABLE
            (
                ArtistID INT NOT NULL PRIMARY KEY,
                ArtistOrder INT NOT NULL UNIQUE
            );
            INSERT INTO @Artists (ArtistID, ArtistOrder)
            SELECT ArtistID, ArtistOrder FROM @ParsedArtists;

            IF EXISTS (
                SELECT 1
                FROM @Artists requested
                LEFT JOIN Artist a WITH (UPDLOCK, HOLDLOCK) ON a.ArtistID = requested.ArtistID
                WHERE a.ArtistID IS NULL OR a.ArtistStatus <> 'Active'
            )
                THROW 58004, 'sp_UpdateConcert: Artist khong ton tai hoac da ngung su dung.', 1;
        END

        -- Luu gia tri cu de ghi audit. Artist la quan he 1-n, nen audit phai
        -- giu ca ID va thu tu thay vi chi ghi ten Concert nhu schema cu.
        DECLARE @OldName NVARCHAR(255) = (SELECT ConcertName FROM Concert WHERE ConcertID = @ConcertID);
        DECLARE @OldArtists NVARCHAR(MAX) = (
            SELECT ArtistID AS [id], ArtistOrder AS [order]
            FROM ConcertArtist
            WHERE ConcertID = @ConcertID
            ORDER BY ArtistOrder
            FOR JSON PATH
        );

        UPDATE Concert
        SET ConcertName         = COALESCE(@ConcertName, ConcertName),
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
            RefundPolicy        = COALESCE(@RefundPolicy, RefundPolicy),
            CancellationDeadlineHours = COALESCE(@CancellationDeadlineHours, CancellationDeadlineHours),
            RefundPercentage    = COALESCE(@RefundPercentage, RefundPercentage)
        WHERE ConcertID = @ConcertID;

        IF @ArtistIDs IS NOT NULL
        BEGIN
            DELETE FROM ConcertArtist WHERE ConcertID = @ConcertID;
            INSERT INTO ConcertArtist (ConcertID, ArtistID, ArtistOrder)
            SELECT @ConcertID, ArtistID, ArtistOrder
            FROM @Artists
            ORDER BY ArtistOrder;
        END

        DECLARE @NewArtists NVARCHAR(MAX) = (
            SELECT ArtistID AS [id], ArtistOrder AS [order]
            FROM ConcertArtist
            WHERE ConcertID = @ConcertID
            ORDER BY ArtistOrder
            FOR JSON PATH
        );

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'CONCERT_UPDATED', 'Concert',
                CAST(@ConcertID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"ConcertName":"' + STRING_ESCAPE(@OldName, 'json') + '","ArtistIds":' + COALESCE(@OldArtists, '[]') + '}',
                '{"ConcertName":"' + STRING_ESCAPE(ISNULL(@ConcertName, @OldName), 'json') + '","ArtistIds":' + COALESCE(@NewArtists, '[]') + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
