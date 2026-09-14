-- ============================================================
-- sp_LockConcertMapRevision (StagePass D.5)
-- Chuyen mot ConcertMapRevision tu Draft sang Locked — tu day la revision
-- DUY NHAT API cong khai doc de ban (xem comment ConcertMapRevision.sql).
-- Admin hoac chinh Organizer cua Concert.
--
-- Neu Map DANG co mot revision Locked khac (truong hop hiem: tao revision
-- ke tiep cho cung Concert, vd sua lai so do sau khi da mo ban — xem
-- docs/stagepass-architecture.md §4.3), revision cu duoc chuyen sang
-- Replaced TRONG CUNG giao dich truoc khi Lock revision moi — bat buoc theo
-- thu tu nay vi UIX_CMR_OneLockedPerMap khong cho hai dong Locked dong thoi.
-- Day la thao tac "hiem, can audit rieng" nen ghi them mot AuditRecord rieng
-- cho hanh dong Replace, tach biet voi AuditRecord cua hanh dong Lock.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_LockConcertMapRevision
(
    @ActorUserID          INT,
    @ConcertMapRevisionID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ConcertMapID INT, @RevisionStatus VARCHAR(32);
        SELECT @ConcertMapID = ConcertMapID, @RevisionStatus = RevisionStatus
        FROM ConcertMapRevision WITH (UPDLOCK, HOLDLOCK)
        WHERE ConcertMapRevisionID = @ConcertMapRevisionID;

        IF @ConcertMapID IS NULL
            THROW 60231, 'sp_LockConcertMapRevision: ConcertMapRevision khong ton tai.', 1;

        DECLARE @ConcertID INT, @OrganizerUserID INT;
        SELECT @ConcertID = cm.ConcertID, @OrganizerUserID = c.OrganizerUserID
        FROM ConcertMap cm JOIN Concert c ON c.ConcertID = cm.ConcertID
        WHERE cm.ConcertMapID = @ConcertMapID;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 60232, 'sp_LockConcertMapRevision: Actor khong co quyen (phai la Organizer cua Concert hoac Admin).', 1;

        IF @RevisionStatus <> 'Draft'
            THROW 60233, 'sp_LockConcertMapRevision: Chi Lock duoc revision dang Draft.', 1;

        IF NOT EXISTS (
            SELECT 1
            FROM ConcertMapRevisionFloor f
            JOIN ConcertMapRevisionSection s ON s.ConcertMapRevisionFloorID = f.ConcertMapRevisionFloorID
            JOIN ConcertMapRevisionSeat sv ON sv.ConcertMapRevisionSectionID = s.ConcertMapRevisionSectionID
            WHERE f.ConcertMapRevisionID = @ConcertMapRevisionID
        )
            THROW 60234, 'sp_LockConcertMapRevision: Revision chua co ghe nao (can it nhat mot Floor/Section/Seat).', 1;

        DECLARE @OldLockedRevisionID INT = (
            SELECT ConcertMapRevisionID FROM ConcertMapRevision
            WHERE ConcertMapID = @ConcertMapID AND RevisionStatus = 'Locked'
        );

        IF @OldLockedRevisionID IS NOT NULL
        BEGIN
            UPDATE ConcertMapRevision SET RevisionStatus = 'Replaced' WHERE ConcertMapRevisionID = @OldLockedRevisionID;

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'CONCERT_MAP_REVISION_REPLACED', 'ConcertMapRevision', CAST(@OldLockedRevisionID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"RevisionStatus":"Replaced","ReplacedByConcertMapRevisionID":' + CAST(@ConcertMapRevisionID AS VARCHAR(20)) + '}');
        END

        UPDATE ConcertMapRevision
        SET RevisionStatus = 'Locked', LockedTimestamp = SYSDATETIME()
        WHERE ConcertMapRevisionID = @ConcertMapRevisionID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'CONCERT_MAP_REVISION_LOCKED', 'ConcertMapRevision', CAST(@ConcertMapRevisionID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"RevisionStatus":"Locked"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
