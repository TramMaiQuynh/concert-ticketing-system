-- ============================================================
-- sp_CreateConcert (BP1 / FR01-FR03)
-- Tao Concert moi o trang thai Draft.
-- Kiem tra: Organizer phai ton tai va dang Active; Artist/Venue ton tai.
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
    @ConcertStatus   VARCHAR(32) = 'Draft',
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

        -- 1. Kiem tra ConcertStatus hop le
        IF @ConcertStatus IS NULL OR @ConcertStatus NOT IN ('Draft','Published','OnSale','SaleClosed','Completed','Cancelled')
            THROW 58001, 'sp_CreateConcert: ConcertStatus khong hop le.', 1;

        -- 2. Kiem tra dates
        IF @EndDatetime <= @StartDatetime
            THROW 58002, 'sp_CreateConcert: EndDatetime phai sau StartDatetime.', 1;

        IF @PurchaseLimit <= 0
            THROW 58003, 'sp_CreateConcert: PurchaseLimit phai lon hon 0.', 1;

        -- 3. Kiem tra references
        IF NOT EXISTS (SELECT 1 FROM Artist WHERE ArtistID = @ArtistID)
            THROW 58004, 'sp_CreateConcert: Artist khong ton tai.', 1;
        IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID = @VenueID)
            THROW 58005, 'sp_CreateConcert: Venue khong ton tai.', 1;
        IF NOT EXISTS (SELECT 1 FROM UserAccount WHERE UserID = @OrganizerUserID AND AccountStatus = 'Active')
            THROW 58006, 'sp_CreateConcert: Organizer khong ton tai hoac khong Active.', 1;

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
                '{"ConcertStatus":"' + @ConcertStatus + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO