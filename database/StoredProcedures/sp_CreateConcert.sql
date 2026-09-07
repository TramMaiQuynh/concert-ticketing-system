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
    @CancellationDeadlineHours INT = 48,
    @RefundPercentage   DECIMAL(5,2) = 100.00,
    @NewConcertID       INT OUTPUT,
    -- Nguoi THUC HIEN lenh, phan biet voi @OrganizerUserID la nguoi SO HUU Concert.
    -- Truoc day SP nay la SP nghiep vu duy nhat khong kiem tra actor, nen mot user
    -- bat ky co the tao Concert va gan quyen so huu cho mot Organizer khac.
    -- NULL = actor chinh la Organizer (truong hop pho bien nhat).
    -- Dat o CUOI danh sach de khong lam lech vi tri cua cac caller goi theo thu tu.
    @ActorUserID        INT = NULL
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
        --
        -- CO Y khong loc theo Role.RoleStatus o day. §12.3.2 dinh nghia RoleStatus la
        -- "vai tro co dang duoc phep PHAN CONG hay khong" - tuc no dieu khien DAU VAO,
        -- khong phai quyen cua nguoi DANG giu vai tro. Loc them RoleStatus tai day se
        -- bien mot thao tac "tam dung cap Role Organizer cho nguoi moi" thanh "moi
        -- Organizer hien huu lap tuc het tao duoc Concert" - mot tac dung phu khong ai
        -- dac ta va rat kho lan ra khi xay ra. Muon go quyen cua mot Organizer cu the
        -- thi dung sp_AssignRole @GrantOrRevoke = 'Revoke', va dieu kien
        -- `ura.AssignmentStatus = 'Active'` ngay duoi day se chan.
        IF NOT EXISTS (
            SELECT 1
            FROM   UserAccount ua
            JOIN   UserRoleAssignment ura ON ura.UserID = ua.UserID AND ura.AssignmentStatus = 'Active'
            JOIN   Role r ON r.RoleID = ura.RoleID AND r.RoleName = 'Organizer'
            WHERE  ua.UserID = @OrganizerUserID AND ua.AccountStatus = 'Active'
        )
            THROW 58006, 'sp_CreateConcert: Organizer khong ton tai, khong Active, hoac khong giu Role Organizer.', 1;

        -- 3c. Uy quyen: chi chinh Organizer do, hoac Admin, moi duoc tao Concert
        --     dung ten Organizer do.
        SET @ActorUserID = ISNULL(@ActorUserID, @OrganizerUserID);

        IF @ActorUserID <> @OrganizerUserID
           AND NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura
                           JOIN   Role r ON r.RoleID = ura.RoleID
                           JOIN   UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                           WHERE  ura.UserID = @ActorUserID AND r.RoleName = 'Admin'
                             AND  ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 58008, 'sp_CreateConcert: Actor khong co quyen tao Concert cho Organizer nay.', 1;

        -- 4. Insert
        INSERT INTO Concert
            (OrganizerUserID, ArtistID, VenueID, ConcertName, StartDatetime, EndDatetime,
             ConcertStatus, SaleStartDatetime, SaleEndDatetime, PurchaseLimit, TemporaryHoldDuration,
             FairAccessEnabled, WaitlistEnabled, SalesPaused, CancellationPolicy, RefundPolicy,
             CancellationDeadlineHours, RefundPercentage)
        VALUES
            (@OrganizerUserID, @ArtistID, @VenueID, @ConcertName, @StartDatetime, @EndDatetime,
             @ConcertStatus, @SaleStartDatetime, @SaleEndDatetime, @PurchaseLimit, @TemporaryHoldDuration,
             @FairAccessEnabled, @WaitlistEnabled, @SalesPaused, @CancellationPolicy, @RefundPolicy,
             @CancellationDeadlineHours, @RefundPercentage);

        SET @NewConcertID = SCOPE_IDENTITY();

        -- 5. Audit
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'CONCERT_CREATED', 'Concert',
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