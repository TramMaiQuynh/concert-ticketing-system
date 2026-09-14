-- ============================================================
-- sp_CreateSeat (BP2 / FR09-FR10)
-- Tao Seat thuoc Zone cua Venue. Chi Admin.
-- Seat.VenueID phai bang Zone.VenueID (TRG_SeatVenueConsistency).
-- UNIQUE(VenueID, SeatCode) dam bao ma ghe duy nhat trong Venue (BR05).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateSeat
(
    @ActorUserID INT,
    @ZoneID      INT,
    @SeatCode    VARCHAR(64),
    @SeatLabel   NVARCHAR(255),
    -- ── Vi tri trong khu (FR11a) — tuy chon, nhung di cung nhau ─────────────
    @SeatRowLabel     NVARCHAR(16) = NULL,
    @SeatColumnNumber INT          = NULL,
    @NewSeatID   INT OUTPUT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
            THROW 58121, 'sp_CreateSeat: Chi Admin duoc tao Seat.', 1;

        IF NOT EXISTS (SELECT 1 FROM Zone WHERE ZoneID = @ZoneID)
            THROW 58122, 'sp_CreateSeat: Zone khong ton tai.', 1;

        IF ISNULL(@SeatCode, '') = ''
            THROW 58123, 'sp_CreateSeat: SeatCode khong duoc de trong.', 1;

        DECLARE @TargetZoneID INT = @ZoneID;

        -- ── Kiem tra vi tri ghe ────────────────────────────────────────────
        -- Hang va cot di cung nhau: chi mot trong hai thi khong dinh vi duoc.
        IF (@SeatRowLabel IS NOT NULL AND @SeatColumnNumber IS NULL)
        OR (@SeatRowLabel IS NULL AND @SeatColumnNumber IS NOT NULL)
            THROW 59821, 'sp_CreateSeat: Hang va so thu tu trong hang phai di cung nhau.', 1;

        IF @SeatColumnNumber IS NOT NULL AND @SeatColumnNumber <= 0
            THROW 59822, 'sp_CreateSeat: So thu tu trong hang phai lon hon 0.', 1;

        DECLARE @ZoneType VARCHAR(24) = (SELECT ZoneType FROM Zone WHERE ZoneID = @TargetZoneID);

        -- Khu ve dung ban theo suc chua, khong co ghe danh so — gan vi tri ghe
        -- vao do la mau thuan voi chinh ban chat cua khu.
        IF @SeatRowLabel IS NOT NULL AND @ZoneType = 'GeneralAdmission'
            THROW 59823, 'sp_CreateSeat: Khong gan duoc vi tri ghe cho khu ve dung.', 1;

        -- Ve doi xung: khu CO GHE thi ghe BAT BUOC phai co vi tri tren luoi.
        -- Truoc day chi cam dat vi tri cho khu ve dung, ma khong buoc phai co vi tri
        -- cho khu co ghe — nen goi thang API chi voi seatCode la tao duoc ghe "khong
        -- toa do" nam trong khu co ghe. Hau qua o giao dien: SeatMap.jsx quy moi ghe
        -- thieu toa do ve cung mot o luoi (cot 1, hang '·'), nen nhieu ghe nhu vay
        -- chong khit len nhau — nguoi dung chi thay va chi bam duoc DUNG MOT ghe,
        -- nhung ghe con lai bien mat khong mot thong bao nao. Chan ngay tu day thay
        -- vi va o tang ve, vi day moi la noi bat bien duoc dinh nghia.
        IF @SeatRowLabel IS NULL AND @ZoneType <> 'GeneralAdmission'
            THROW 59825, 'sp_CreateSeat: Ghe trong khu co ghe phai co hang va so thu tu trong hang.', 1;

        -- Bao loi ro rang thay vi de nguoi dung nhan mot vi pham chi muc kho hieu.
        IF @SeatRowLabel IS NOT NULL
           AND EXISTS (SELECT 1 FROM Seat
                       WHERE ZoneID = @ZoneID
                         AND SeatRowLabel = @SeatRowLabel
                         AND SeatColumnNumber = @SeatColumnNumber
                         AND SeatStatus = 'Active')
            THROW 59824, 'sp_CreateSeat: Vi tri nay trong khu da co ghe khac.', 1;

        DECLARE @VenueID INT = (SELECT VenueID FROM Zone WHERE ZoneID = @ZoneID);

        INSERT INTO Seat (ZoneID, VenueID, SeatCode, SeatLabel, SeatRowLabel, SeatColumnNumber)
        VALUES (@ZoneID, @VenueID, @SeatCode, @SeatLabel, @SeatRowLabel, @SeatColumnNumber);

        SET @NewSeatID = SCOPE_IDENTITY();

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'SEAT_CREATED', 'Seat', CAST(@NewSeatID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"SeatCode":"' + STRING_ESCAPE(@SeatCode, 'json') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO