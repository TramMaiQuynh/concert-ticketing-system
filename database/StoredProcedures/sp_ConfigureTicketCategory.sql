-- ============================================================
-- sp_ConfigureTicketCategory (BP3 / FR12)
-- Them hoac cap nhat Ticket Category cho Concert.
-- Chi Organizer cua Concert hoac Admin.
-- Neu @TicketCategoryID IS NULL -> Tao moi
-- Neu @TicketCategoryID IS NOT NULL -> Cap nhat (BasePrice, Name)
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureTicketCategory
(
    @ActorUserID         INT,
    @ConcertID           INT,
    @CategoryName        NVARCHAR(255),
    @CategoryDescription NVARCHAR(500),
    @BasePrice           DECIMAL(18,0),
    @TicketCategoryID    INT = NULL OUTPUT
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
            
        IF @BasePrice < 0
            THROW 58205, 'sp_ConfigureTicketCategory: BasePrice phai lon hon hoac bang 0.', 1;

        IF @TicketCategoryID IS NULL OR @TicketCategoryID <= 0
        BEGIN
            -- INSERT
            INSERT INTO TicketCategory (ConcertID, CategoryName, CategoryDescription, CategoryStatus, BasePrice)
            VALUES (@ConcertID, @CategoryName, @CategoryDescription, 'Active', @BasePrice);

            SET @TicketCategoryID = SCOPE_IDENTITY();

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TICKET_CATEGORY_CREATED', 'TicketCategory',
                    CAST(@TicketCategoryID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                    '{"CategoryName":"' + @CategoryName + '","BasePrice":' + CAST(@BasePrice AS VARCHAR) + '}');
        END
        ELSE
        BEGIN
            -- UPDATE
            IF NOT EXISTS (SELECT 1 FROM TicketCategory WHERE TicketCategoryID = @TicketCategoryID AND ConcertID = @ConcertID)
                THROW 58204, 'sp_ConfigureTicketCategory: TicketCategoryID khong hop le hoac khong thuoc ve Concert nay.', 1;
                
            UPDATE TicketCategory
            SET CategoryName = @CategoryName,
                CategoryDescription = @CategoryDescription,
                BasePrice = @BasePrice
            WHERE TicketCategoryID = @TicketCategoryID;
            
            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TICKET_CATEGORY_UPDATED', 'TicketCategory',
                    CAST(@TicketCategoryID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"CategoryName":"' + @CategoryName + '","BasePrice":' + CAST(@BasePrice AS VARCHAR) + '}');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO