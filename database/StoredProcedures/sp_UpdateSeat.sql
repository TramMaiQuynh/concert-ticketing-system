-- ============================================================
-- sp_UpdateSeat (BP2 / FR09-FR10, FR59b / BR50e)
-- Cap nhat thong tin Seat va chuyen SeatStatus Active <-> Retired. CHI Admin.
--
-- Ly do SP nay ton tai: giong sp_UpdateZone - sp_AddEventSeats doc SeatStatus
-- (THROW 58219) nhung truoc day khong co duong ghi nao dat duoc 'Retired'.
-- Retired = ghe da thao do khi cai tao Venue: khong duoc chon vao kho ve MOI (FR11),
-- nhung Ticket lich su tro toi no van truy van binh thuong (khong Hard Delete).
--
-- KHONG cho doi ZoneID/VenueID/SeatCode: do la dinh danh vat ly cua ghe. Doi chung
-- se pha bat bien Seat.VenueID = Zone.VenueID (TRG_SeatVenueConsistency) va lam moi
-- EventSeat lich su tro toi mot vi tri khac. Ghe moi thi tao ghe moi.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateSeat
(
    @ActorUserID INT,
    @SeatID      INT,
    @SeatLabel   NVARCHAR(255) = NULL,
    @SeatStatus  VARCHAR(32)   = NULL,
    -- ── Vi tri trong khu (FR11a) — NULL = giu nguyen ────────────────────────
    @SeatRowLabel     NVARCHAR(16) = NULL,
    @SeatColumnNumber INT          = NULL
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
            THROW 59421, 'sp_UpdateSeat: Chi Admin duoc cap nhat Seat.', 1;

        DECLARE @OldStatus VARCHAR(32);
        SELECT @OldStatus = SeatStatus FROM Seat WITH (UPDLOCK) WHERE SeatID = @SeatID;

        IF @OldStatus IS NULL
            THROW 59422, 'sp_UpdateSeat: Seat khong ton tai.', 1;

        DECLARE @TargetZoneID INT = (SELECT ZoneID FROM Seat WHERE SeatID = @SeatID);

        -- ── Kiem tra vi tri ghe ────────────────────────────────────────────
        -- Hang va cot di cung nhau: chi mot trong hai thi khong dinh vi duoc.
        IF (@SeatRowLabel IS NOT NULL AND @SeatColumnNumber IS NULL)
        OR (@SeatRowLabel IS NULL AND @SeatColumnNumber IS NOT NULL)
            THROW 59821, 'sp_UpdateSeat: Hang va so thu tu trong hang phai di cung nhau.', 1;

        IF @SeatColumnNumber IS NOT NULL AND @SeatColumnNumber <= 0
            THROW 59822, 'sp_UpdateSeat: So thu tu trong hang phai lon hon 0.', 1;

        -- Khu ve dung ban theo suc chua, khong co ghe danh so — gan vi tri ghe
        -- vao do la mau thuan voi chinh ban chat cua khu.
        IF @SeatRowLabel IS NOT NULL
           AND (SELECT ZoneType FROM Zone WHERE ZoneID = @TargetZoneID) = 'GeneralAdmission'
            THROW 59823, 'sp_UpdateSeat: Khong gan duoc vi tri ghe cho khu ve dung.', 1;

        IF @SeatRowLabel IS NOT NULL
           AND EXISTS (SELECT 1 FROM Seat
                       WHERE ZoneID = @TargetZoneID
                         AND SeatRowLabel = @SeatRowLabel
                         AND SeatColumnNumber = @SeatColumnNumber
                         AND SeatStatus = 'Active'
                         AND SeatID <> @SeatID)
            THROW 59824, 'sp_UpdateSeat: Vi tri nay trong khu da co ghe khac.', 1;

        IF @SeatStatus IS NOT NULL AND @SeatStatus NOT IN ('Active', 'Retired')
            THROW 59423, 'sp_UpdateSeat: SeatStatus phai la Active hoac Retired.', 1;

        IF @SeatStatus = 'Retired' AND @OldStatus = 'Active'
           AND EXISTS (SELECT 1
                       FROM   EventSeat es
                       JOIN   Concert c ON c.ConcertID = es.ConcertID
                       WHERE  es.SeatID = @SeatID
                         AND  c.ConcertStatus IN ('Draft', 'Published', 'OnSale', 'SaleClosed'))
            THROW 59425, 'sp_UpdateSeat: Khong the Retire Seat dang nam trong kho ve cua Concert chua ket thuc.', 1;

        UPDATE Seat
        SET    SeatLabel  = COALESCE(@SeatLabel, SeatLabel),
               SeatStatus = COALESCE(@SeatStatus, SeatStatus),
               SeatRowLabel     = COALESCE(@SeatRowLabel, SeatRowLabel),
               SeatColumnNumber = COALESCE(@SeatColumnNumber, SeatColumnNumber)
        WHERE  SeatID = @SeatID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'SEAT_UPDATED', 'Seat', CAST(@SeatID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"SeatStatus":"' + @OldStatus + '"}',
                '{"SeatStatus":"' + ISNULL(@SeatStatus, @OldStatus) + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
