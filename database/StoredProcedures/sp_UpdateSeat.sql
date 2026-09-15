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

        DECLARE @OldStatus VARCHAR(32), @TargetZoneID INT,
                @OldRowLabel NVARCHAR(16), @OldColumnNumber INT;
        SELECT @OldStatus = SeatStatus, @TargetZoneID = ZoneID,
               @OldRowLabel = SeatRowLabel, @OldColumnNumber = SeatColumnNumber
        FROM Seat WITH (UPDLOCK, HOLDLOCK)
        WHERE SeatID = @SeatID;

        IF @OldStatus IS NULL
            THROW 59422, 'sp_UpdateSeat: Seat khong ton tai.', 1;

        -- ── Kiem tra vi tri ghe ────────────────────────────────────────────
        IF @SeatRowLabel IS NOT NULL
        BEGIN
            SET @SeatRowLabel = NULLIF(LTRIM(RTRIM(@SeatRowLabel)), '');
            IF @SeatRowLabel IS NULL
                THROW 59825, 'sp_UpdateSeat: Ghe trong khu co ghe phai co hang va so thu tu trong hang.', 1;
        END

        IF @SeatColumnNumber IS NOT NULL AND @SeatColumnNumber <= 0
            THROW 59822, 'sp_UpdateSeat: So thu tu trong hang phai lon hon 0.', 1;

        -- PATCH cho phep doi rieng hang hoac cot: NULL nghia la giu gia tri cu.
        -- Kiem tra tren GIA TRI SAU KHI HOP NHAT de khong bat client gui lai
        -- truong khong thay doi, nhung van chan ghe du lieu cu chua dinh vi.
        DECLARE @FinalRowLabel NVARCHAR(16) = COALESCE(@SeatRowLabel, @OldRowLabel),
                @FinalColumnNumber INT = COALESCE(@SeatColumnNumber, @OldColumnNumber),
                @FinalStatus VARCHAR(32) = COALESCE(@SeatStatus, @OldStatus);

        -- Bat buoc co vi tri chi voi ghe CON HOAT DONG sau khi cap nhat. Ghe Retired
        -- khong duoc ve tren so do nua, nen doi no phai co toa do la doi mot thu khong
        -- phuc vu gi. Day cung la ranh gioi ma phan con lai cua he thong da dung san:
        -- ca ba noi kiem trung vi tri (sp_CreateSeat, sp_UpdateSeat ngay duoi, va
        -- sp_CreateSeatsBatch) deu chi xet cac dong co SeatStatus = 'Active'.
        --
        -- Kiem vo dieu kien thi mot ghe chua dinh vi (du lieu cu, hoac chen thang vao
        -- bang) khong con duong nao ra: khong Retire duoc, khong doi ten duoc, va cach
        -- duy nhat de dong no lai la bia ra mot toa do cho chinh ghe sap ngung dung -
        -- toa do do lai co the dam vao ghe khac va bi 59824 chan not.
        IF @FinalStatus = 'Active' AND (@FinalRowLabel IS NULL OR @FinalColumnNumber IS NULL)
            THROW 59825, 'sp_UpdateSeat: Ghe trong khu co ghe phai co hang va so thu tu trong hang.', 1;

        IF EXISTS (SELECT 1 FROM Seat WITH (UPDLOCK, HOLDLOCK)
                       WHERE ZoneID = @TargetZoneID
                         AND SeatRowLabel = @FinalRowLabel
                         AND SeatColumnNumber = @FinalColumnNumber
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
               SeatRowLabel     = @FinalRowLabel,
               SeatColumnNumber = @FinalColumnNumber
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
