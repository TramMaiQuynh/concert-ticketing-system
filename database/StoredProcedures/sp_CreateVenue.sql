-- ============================================================
-- sp_CreateVenue (BP2 / FR07)
-- Tao Venue moi. Chi Admin (kiem tra Role Admin).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateVenue
(
    @ActorUserID INT,
    @VenueName   NVARCHAR(255),
    @Address     NVARCHAR(500),
    @NewVenueID  INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 58101, 'sp_CreateVenue: Chi Admin duoc tao Venue.', 1;

        IF ISNULL(@VenueName, '') = ''
            THROW 58102, 'sp_CreateVenue: VenueName khong duoc de trong.', 1;

        -- Cat khoang trang dau/cuoi TRUOC khi luu.
        --
        -- Truoc day SP nay ghi NGUYEN gia tri nhan duoc, trong khi sp_UpdateVenue lai
        -- luu LTRIM(RTRIM(@VenueName)) — cung mot cot, hai hanh vi: tao "Nha hat A "
        -- roi sua mot truong khac thi ten van con khoang trang, con sua ten thi bi cat.
        -- Da kiem chung bang thuc thi tren database: tao voi ten '  X  ' luu ra
        -- '[  X  ]', sua thanh '  Y  ' luu ra '[Y]'.
        -- sp_CreateArtist (dong 38) va sp_CreateSeat (dong 33-34) deu da cat tu truoc,
        -- nen sp_CreateVenue la truong hop lech khoi quy uoc cua chinh he thong.
        -- Hau qua that: hai dia diem trong giong het nhau tren giao dien nhung khac
        -- nhau khi so sanh, va ten co khoang trang cuoi lam moi phep tra cuu theo ten
        -- trai y muon.
        SET @VenueName = LTRIM(RTRIM(@VenueName));

        INSERT INTO Venue (VenueName, Address, VenueStatus, CreatedTimestamp, UpdatedTimestamp)
        VALUES (@VenueName, @Address, 'Active', SYSDATETIME(), SYSDATETIME());

        SET @NewVenueID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'VENUE_CREATED', 'Venue', CAST(@NewVenueID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"VenueName":"' + STRING_ESCAPE(@VenueName, 'json') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO