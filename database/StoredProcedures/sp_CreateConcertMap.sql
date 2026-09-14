-- ============================================================
-- sp_CreateConcertMap (StagePass D.5)
-- Tao ConcertMap — "diem neo" giu danh tinh so do cua mot Concert, tach
-- biet voi lich su cac ConcertMapRevision cua no. Admin hoac chinh
-- Organizer cua Concert (dung khuon uy quyen cua sp_ConfigureTicketCategory:
-- @ActorUserID = OrganizerUserID HOAC Admin).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateConcertMap
(
    @ActorUserID    INT,
    @ConcertID      INT,
    @NewConcertMapID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT;
        SELECT @OrganizerUserID = OrganizerUserID FROM Concert WHERE ConcertID = @ConcertID;

        IF @OrganizerUserID IS NULL
            THROW 60201, 'sp_CreateConcertMap: Concert khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 60202, 'sp_CreateConcertMap: Actor khong co quyen (phai la Organizer cua Concert hoac Admin).', 1;

        IF EXISTS (SELECT 1 FROM ConcertMap WHERE ConcertID = @ConcertID)
            THROW 60203, 'sp_CreateConcertMap: Concert nay da co ConcertMap.', 1;

        INSERT INTO ConcertMap (ConcertID) VALUES (@ConcertID);
        SET @NewConcertMapID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'CONCERT_MAP_CREATED', 'ConcertMap', CAST(@NewConcertMapID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"ConcertID":' + CAST(@ConcertID AS VARCHAR(20)) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
