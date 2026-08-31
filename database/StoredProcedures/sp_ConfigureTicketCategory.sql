-- ============================================================
-- sp_ConfigureTicketCategory (BP3 / FR12)
-- Them Ticket Category moi cho Concert. Chi Organizer cua Concert
-- hoac Admin.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureTicketCategory
(
    @ActorUserID   INT,
    @ConcertID     INT,
    @CategoryName  NVARCHAR(255),
    @CategoryDescription NVARCHAR(500),
    @NewTicketCategoryID INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT;
        SELECT @OrganizerUserID = OrganizerUserID FROM Concert WHERE ConcertID = @ConcertID;

        IF @OrganizerUserID IS NULL
            THROW 58201, 'sp_ConfigureTicketCategory: Concert khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 58202, 'sp_ConfigureTicketCategory: Actor khong co quyen.', 1;

        IF ISNULL(@CategoryName, '') = ''
            THROW 58203, 'sp_ConfigureTicketCategory: CategoryName khong duoc de trong.', 1;

        INSERT INTO TicketCategory (ConcertID, CategoryName, CategoryDescription, CategoryStatus)
        VALUES (@ConcertID, @CategoryName, @CategoryDescription, 'Active');

        SET @NewTicketCategoryID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'TICKET_CATEGORY_CREATED', 'TicketCategory',
                CAST(@NewTicketCategoryID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"CategoryName":"' + @CategoryName + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO