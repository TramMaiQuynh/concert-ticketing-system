-- ============================================================
-- sp_UpdateArtist (BP1 / FR03, FR59b / BR50e)
-- Cap nhat thong tin Artist va chuyen trang thai Active <-> Retired. CHI Admin.
-- Retired = ngung su dung cho Concert MOI; Concert lich su van tham chieu binh thuong,
-- do do khong bao gio Hard Delete Artist (BR50a).
-- Tham so NULL = giu nguyen gia tri hien tai (COALESCE).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateArtist
(
    @ActorUserID       INT,
    @ArtistID          INT,
    @ArtistName        NVARCHAR(255) = NULL,
    @ArtistDescription NVARCHAR(500) = NULL,
    @ArtistStatus      VARCHAR(32)   = NULL
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
                                                AND  uaAdm.AccountStatus = 'Active')
            THROW 59111, 'sp_UpdateArtist: Chi Admin duoc cap nhat Artist.', 1;

        DECLARE @OldStatus VARCHAR(32);
        SELECT @OldStatus = ArtistStatus
        FROM   Artist WITH (UPDLOCK)
        WHERE  ArtistID = @ArtistID;

        IF @OldStatus IS NULL
            THROW 59112, 'sp_UpdateArtist: Artist khong ton tai.', 1;

        IF @ArtistStatus IS NOT NULL AND @ArtistStatus NOT IN ('Active', 'Retired')
            THROW 59113, 'sp_UpdateArtist: ArtistStatus phai la Active hoac Retired.', 1;

        IF @ArtistName IS NOT NULL AND ISNULL(LTRIM(RTRIM(@ArtistName)), '') = ''
            THROW 59114, 'sp_UpdateArtist: ArtistName khong duoc de trong.', 1;

        -- LI00/BR54: Concert chi Published khi da co Artist. Khong cho Retire mot Artist
        -- dang duoc Concert CHUA ket thuc tham chieu - neu khong, Concert do se giu
        -- tham chieu toi mot Artist khong con su dung duoc cho den khi dien xong.
        IF @ArtistStatus = 'Retired' AND @OldStatus = 'Active'
           AND EXISTS (SELECT 1
                       FROM ConcertArtist ca
                       JOIN Concert c ON c.ConcertID = ca.ConcertID
                       WHERE ca.ArtistID = @ArtistID
                         AND c.ConcertStatus IN ('Draft', 'Published', 'OnSale', 'SaleClosed'))
            THROW 59115, 'sp_UpdateArtist: Khong the Retire Artist dang duoc Concert chua ket thuc tham chieu.', 1;

        UPDATE Artist
        SET    ArtistName        = COALESCE(LTRIM(RTRIM(@ArtistName)), ArtistName),
               ArtistDescription = COALESCE(@ArtistDescription, ArtistDescription),
               ArtistStatus      = COALESCE(@ArtistStatus, ArtistStatus)
        WHERE  ArtistID = @ArtistID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'ARTIST_UPDATED', 'Artist',
                CAST(@ArtistID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"ArtistStatus":"' + @OldStatus + '"}',
                '{"ArtistStatus":"' + ISNULL(@ArtistStatus, @OldStatus) + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
