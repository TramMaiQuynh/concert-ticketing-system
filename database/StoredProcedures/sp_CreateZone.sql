-- ============================================================
-- sp_CreateZone (BP2 / FR08)
-- Tao Zone thuoc Venue. Chi Admin.
-- UNIQUE(VenueID, ZoneCode) dam bao khong trung ma Zone.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateZone
(
    @ActorUserID    INT,
    @VenueID        INT,
    @ZoneCode       VARCHAR(64),
    @ZoneName       NVARCHAR(255),
    @NewZoneID      INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
            THROW 58111, 'sp_CreateZone: Chi Admin duoc tao Zone.', 1;

        IF NOT EXISTS (SELECT 1 FROM Venue WHERE VenueID = @VenueID)
            THROW 58112, 'sp_CreateZone: Venue khong ton tai.', 1;

        IF ISNULL(@ZoneCode, '') = ''
            THROW 58113, 'sp_CreateZone: ZoneCode khong duoc de trong.', 1;

        INSERT INTO Zone (VenueID, ZoneCode, ZoneName)
        VALUES (@VenueID, @ZoneCode, @ZoneName);

        SET @NewZoneID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'ZONE_CREATED', 'Zone', CAST(@NewZoneID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"ZoneCode":"' + @ZoneCode + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO