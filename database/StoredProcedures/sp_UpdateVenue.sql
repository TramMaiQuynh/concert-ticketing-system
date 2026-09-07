-- ============================================================
-- sp_UpdateVenue (BP2 / FR07, FR59b / BR50e)
-- Cap nhat thong tin Venue va chuyen VenueStatus Active <-> Inactive. CHI Admin.
--
-- Ly do SP nay ton tai: VenueStatus co domain {Active, Inactive} (§18.4.1) nhung
-- truoc day KHONG co bat ky duong ghi nao dat duoc 'Inactive' - sp_CreateVenue chi
-- ghi 'Active' luc INSERT. Mot gia tri domain khong co ben ghi thi khong phai la
-- trang thai, chi la chu chet (§24.4). Venue bi Concert lich su tham chieu nen
-- khong the Hard Delete (BR50a), vay ngung su dung PHAI di qua trang thai.
--
-- Tham so NULL = giu nguyen gia tri hien tai (COALESCE).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateVenue
(
    @ActorUserID INT,
    @VenueID     INT,
    @VenueName   NVARCHAR(255) = NULL,
    @Address     NVARCHAR(500) = NULL,
    @VenueStatus VARCHAR(32)   = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura
                       JOIN   Role r ON r.RoleID = ura.RoleID
                       JOIN   UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE  ura.UserID = @ActorUserID
                         AND  r.RoleName = 'Admin'
                         AND  ura.AssignmentStatus = 'Active'
                         AND  uaAdm.AccountStatus  = 'Active')
            THROW 59401, 'sp_UpdateVenue: Chi Admin duoc cap nhat Venue.', 1;

        DECLARE @OldStatus VARCHAR(32);
        SELECT @OldStatus = VenueStatus FROM Venue WITH (UPDLOCK) WHERE VenueID = @VenueID;

        IF @OldStatus IS NULL
            THROW 59402, 'sp_UpdateVenue: Venue khong ton tai.', 1;

        IF @VenueStatus IS NOT NULL AND @VenueStatus NOT IN ('Active', 'Inactive')
            THROW 59403, 'sp_UpdateVenue: VenueStatus phai la Active hoac Inactive.', 1;

        IF @VenueName IS NOT NULL AND ISNULL(LTRIM(RTRIM(@VenueName)), '') = ''
            THROW 59404, 'sp_UpdateVenue: VenueName khong duoc de trong.', 1;

        -- Khong duoc ngung su dung mot Venue ma Concert CHUA dien xong dang dung:
        -- Concert do se tro toi mot dia diem khong con hoat dong cho toi ngay dien.
        IF @VenueStatus = 'Inactive' AND @OldStatus = 'Active'
           AND EXISTS (SELECT 1 FROM Concert
                       WHERE VenueID = @VenueID
                         AND ConcertStatus IN ('Draft', 'Published', 'OnSale', 'SaleClosed'))
            THROW 59405, 'sp_UpdateVenue: Khong the ngung su dung Venue dang duoc Concert chua ket thuc tham chieu.', 1;

        UPDATE Venue
        SET    VenueName        = COALESCE(LTRIM(RTRIM(@VenueName)), VenueName),
               Address          = COALESCE(@Address, Address),
               VenueStatus      = COALESCE(@VenueStatus, VenueStatus),
               UpdatedTimestamp = SYSDATETIME()
        WHERE  VenueID = @VenueID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'VENUE_UPDATED', 'Venue', CAST(@VenueID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"VenueStatus":"' + @OldStatus + '"}',
                '{"VenueStatus":"' + ISNULL(@VenueStatus, @OldStatus) + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
