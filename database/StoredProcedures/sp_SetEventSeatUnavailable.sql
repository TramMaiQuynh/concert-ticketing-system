-- ============================================================
-- sp_SetEventSeatUnavailable (BP3 / BR08)
-- Danh dau EventSeat la Unavailable (ghe hong, giu cho dac biet)
-- hoac tra lai Available. Bat buoc co Reason khi Unavailable.
-- Chi Organizer cua Concert hoac Admin.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_SetEventSeatUnavailable
(
    @ActorUserID   INT,
    @EventSeatID   INT,
    @Unavailable   BIT,
    @Reason        NVARCHAR(500) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT, @ConcertID INT, @CurrentStatus VARCHAR(32);
        SELECT @OrganizerUserID = c.OrganizerUserID, @ConcertID = c.ConcertID, @CurrentStatus = es.InventoryStatus
        FROM EventSeat es
        JOIN Concert c ON c.ConcertID = es.ConcertID
        WHERE es.EventSeatID = @EventSeatID;

        IF @ConcertID IS NULL
            THROW 58801, 'sp_SetEventSeatUnavailable: EventSeat khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 58802, 'sp_SetEventSeatUnavailable: Actor khong co quyen.', 1;

        -- Chi cho phep thay doi trang thai neu EventSeat khong bi chien boi Booking
        IF @CurrentStatus NOT IN ('Available', 'Unavailable')
            THROW 58803, 'sp_SetEventSeatUnavailable: Chi thay doi duoc khi trang thai Available hoac Unavailable.', 1;

        IF @Unavailable = 1 AND (ISNULL(@Reason, '') = '')
            THROW 58804, 'sp_SetEventSeatUnavailable: Phai cung cap Reason khi danh dau Unavailable (BR09).', 1;

        IF @Unavailable = 1
            UPDATE EventSeat
            SET InventoryStatus = 'Unavailable', UnavailabilityReason = @Reason
            WHERE EventSeatID = @EventSeatID;
        ELSE
            UPDATE EventSeat
            SET InventoryStatus = 'Available', UnavailabilityReason = NULL
            WHERE EventSeatID = @EventSeatID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'EVENT_SEAT_STATUS_CHANGED', 'EventSeat',
                CAST(@EventSeatID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"InventoryStatus":"' + CASE WHEN @Unavailable = 1 THEN 'Unavailable' ELSE 'Available' END + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO