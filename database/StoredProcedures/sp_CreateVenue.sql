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
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
            THROW 58101, 'sp_CreateVenue: Chi Admin duoc tao Venue.', 1;

        IF ISNULL(@VenueName, '') = ''
            THROW 58102, 'sp_CreateVenue: VenueName khong duoc de trong.', 1;

        INSERT INTO Venue (VenueName, Address, VenueStatus, CreatedTimestamp, UpdatedTimestamp)
        VALUES (@VenueName, @Address, 'Active', SYSDATETIME(), SYSDATETIME());

        SET @NewVenueID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'VENUE_CREATED', 'Venue', CAST(@NewVenueID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"VenueName":"' + @VenueName + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO