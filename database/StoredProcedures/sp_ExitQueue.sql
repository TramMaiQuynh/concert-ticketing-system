-- ============================================================
-- sp_ExitQueue (BP11 / FR67 / BR45-BR48)
-- Customer roi Virtual Queue (tu nguyen) hoac he thong thu hoi
-- quyen admission (het han, mat dieu kien).
-- Chuyen QueueEntry 'Waiting' hoac 'Admitted' -> 'Exited'.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ExitQueue
(
    @QueueEntryID INT,
    @ActorUserID  INT,
    @Reason       NVARCHAR(200) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @CurrentStatus VARCHAR(32), @OwnerID INT;
        SELECT @CurrentStatus = QueueStatus, @OwnerID = CustomerUserID
        FROM   QueueEntry
        WHERE  QueueEntryID = @QueueEntryID;

        IF @CurrentStatus IS NULL
            THROW 58901, 'sp_ExitQueue: QueueEntry khong ton tai.', 1;

        -- Quyen: chinh Customer so huu entry, hoac System (het han)
        IF @ActorUserID <> @OwnerID
           AND NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                           WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
            THROW 58902, 'sp_ExitQueue: Actor khong co quyen.', 1;

        IF @CurrentStatus NOT IN ('Waiting', 'Admitted')
            THROW 58903, 'sp_ExitQueue: Chi co the exit khi dang Waiting hoac Admitted.', 1;

        UPDATE QueueEntry
        SET    QueueStatus   = 'Exited',
               ExitTimestamp = SYSDATETIME()
        WHERE  QueueEntryID = @QueueEntryID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'QUEUE_EXITED', 'QueueEntry',
                CAST(@QueueEntryID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"QueueStatus":"Exited","Reason":"' + ISNULL(@Reason, '') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO