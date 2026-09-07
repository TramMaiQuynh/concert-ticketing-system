-- ============================================================
-- sp_CreateArtist (BP1 / FR03 / BR50e)
-- Tao Artist moi trong danh muc dung chung. CHI Admin.
-- Ly do chi Admin: Artist la du lieu danh muc dung chung giua moi Organizer
-- (§12.6.1). Neu moi Organizer tu tao, he thong se co nhieu bien the cua cung
-- mot nghe si va tim kiem/bao cao theo nghe si se sai.
-- KHONG dat UNIQUE tren ArtistName: hai nghe si khac nhau co the trung ten hop le,
-- dong thoi UNIQUE khong chan duoc bien the dau/khoang trang cua cung mot ten.
-- Chong trung la trach nhiem cua luong tim-truoc-khi-tao o tang ung dung.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateArtist
(
    @ActorUserID       INT,
    @ArtistName        NVARCHAR(255),
    @ArtistDescription NVARCHAR(500) = NULL,
    @NewArtistID       INT OUTPUT
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
            THROW 59101, 'sp_CreateArtist: Chi Admin duoc tao Artist.', 1;

        IF ISNULL(LTRIM(RTRIM(@ArtistName)), '') = ''
            THROW 59102, 'sp_CreateArtist: ArtistName khong duoc de trong.', 1;

        INSERT INTO Artist (ArtistName, ArtistDescription, ArtistStatus)
        VALUES (LTRIM(RTRIM(@ArtistName)), @ArtistDescription, 'Active');

        SET @NewArtistID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'ARTIST_CREATED', 'Artist',
                CAST(@NewArtistID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"ArtistName":"' + STRING_ESCAPE(@ArtistName, 'json') + '","ArtistStatus":"Active"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
