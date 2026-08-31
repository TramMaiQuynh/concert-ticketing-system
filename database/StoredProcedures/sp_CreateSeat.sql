-- ============================================================
-- sp_CreateSeat (BP2 / FR09-FR10)
-- Tao Seat thuoc Zone cua Venue. Chi Admin.
-- Seat.VenueID phai bang Zone.VenueID (TRG_SeatVenueConsistency).
-- UNIQUE(VenueID, SeatCode) dam bao ma ghe duy nhat trong Venue (BR05).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateSeat
(
    @ActorUserID INT,
    @ZoneID      INT,
    @SeatCode    VARCHAR(64),
    @SeatLabel   NVARCHAR(255),
    @NewSeatID   INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
            THROW 58121, 'sp_CreateSeat: Chi Admin duoc tao Seat.', 1;

        IF NOT EXISTS (SELECT 1 FROM Zone WHERE ZoneID = @ZoneID)
            THROW 58122, 'sp_CreateSeat: Zone khong ton tai.', 1;

        IF ISNULL(@SeatCode, '') = ''
            THROW 58123, 'sp_CreateSeat: SeatCode khong duoc de trong.', 1;

        DECLARE @VenueID INT = (SELECT VenueID FROM Zone WHERE ZoneID = @ZoneID);

        INSERT INTO Seat (ZoneID, VenueID, SeatCode, SeatLabel)
        VALUES (@ZoneID, @VenueID, @SeatCode, @SeatLabel);

        SET @NewSeatID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'SEAT_CREATED', 'Seat', CAST(@NewSeatID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"SeatCode":"' + @SeatCode + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO