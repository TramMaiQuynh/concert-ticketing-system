-- ============================================================
-- sp_UpdateConcertStatus (BP1/BP4 / FR16 / BR49)
-- Chuyen trang thai Concert theo state machine.
-- Cac chuyen doi hop le duoc stip boi TRG_Concert_StateTransition;
-- SP chi kiem tra quyen truoc khi UPDATE.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateConcertStatus
(
    @ConcertID   INT,
    @ActorUserID INT,
    @NewStatus   VARCHAR(32)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @NewStatus NOT IN ('Draft','Published','OnSale','SaleClosed','Completed','Cancelled')
            THROW 58020, 'sp_UpdateConcertStatus: ConcertStatus khong hop le.', 1;

        DECLARE @OrganizerUserID INT, @CurrentStatus VARCHAR(32);
        SELECT @OrganizerUserID = OrganizerUserID, @CurrentStatus = ConcertStatus
        FROM Concert WHERE ConcertID = @ConcertID;

        IF @CurrentStatus IS NULL
            THROW 58021, 'sp_UpdateConcertStatus: Concert khong ton tai.', 1;

        -- Quyen: Organizer cua Concert hoac Admin
        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 58022, 'sp_UpdateConcertStatus: Actor khong co quyen.', 1;

        -- UPDATE -> TRG_Concert_StateTransition tu chan chuyen doi khong hop le
        UPDATE Concert SET ConcertStatus = @NewStatus WHERE ConcertID = @ConcertID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'CONCERT_STATUS_CHANGED', 'Concert',
                CAST(@ConcertID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"ConcertStatus":"' + @CurrentStatus + '"}',
                '{"ConcertStatus":"' + @NewStatus + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO