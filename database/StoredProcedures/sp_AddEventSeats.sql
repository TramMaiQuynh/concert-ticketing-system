-- ============================================================
-- sp_AddEventSeats (BP3 / FR11, FR13)
-- Them cac Seat vao kho ve (EventSeat) cua Concert voi TicketCategory
-- va SalePrice nhat dinh. Doc quyen theo Concert (Organizer/Admin).
-- DR-07 (Seat thuoc Venue cua Concert) duoc enforce boi TRG_EventSeatVenue.
-- Ghi nhom: chi nhan nhung Seat hop le; neu co Seat khong hop le -> rollback tat ca.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AddEventSeats
(
    @ActorUserID  INT,
    @ConcertID    INT,
    @TicketCategoryID INT,
    @SeatIDs      NVARCHAR(MAX)   -- CSV: '1,2,3,4'
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT, @ConcertStatus VARCHAR(32);
        SELECT @OrganizerUserID = OrganizerUserID, @ConcertStatus = ConcertStatus
        FROM   Concert WHERE ConcertID = @ConcertID;

        IF @ConcertStatus IS NULL
            THROW 58211, 'sp_AddEventSeats: Concert khong ton tai.', 1;

        -- Precondition BP3: chi cau hinh kho ve khi Concert o trang thai Draft hoac Published.
        IF @ConcertStatus NOT IN ('Draft', 'Published')
            THROW 58218, 'sp_AddEventSeats (BP3): Chi them EventSeat khi Concert o trang thai Draft hoac Published.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 58212, 'sp_AddEventSeats: Actor khong co quyen.', 1;

        DECLARE @SalePrice DECIMAL(18,0);

        SELECT @SalePrice = BasePrice
        FROM TicketCategory
        WHERE TicketCategoryID = @TicketCategoryID AND ConcertID = @ConcertID AND CategoryStatus = 'Active';

        IF @SalePrice IS NULL
            THROW 58213, 'sp_AddEventSeats: TicketCategory khong thuoc Concert hoac khong Active.', 1;

        -- Parse CSV
        DECLARE @SeatRequests TABLE (SeatID INT NOT NULL PRIMARY KEY);
        INSERT INTO @SeatRequests (SeatID)
        SELECT DISTINCT CAST(value AS INT)
        FROM STRING_SPLIT(@SeatIDs, ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        IF NOT EXISTS (SELECT 1 FROM @SeatRequests)
            THROW 58215, 'sp_AddEventSeats: Danh sach Seat rong.', 1;

        -- Kiem tra tat ca Seat ton tai va dang Available (chua nam trong inventory Concert nay)
        IF EXISTS (
            SELECT 1 FROM @SeatRequests sr
            LEFT JOIN Seat s ON s.SeatID = sr.SeatID
            WHERE s.SeatID IS NULL
        )
            THROW 58216, 'sp_AddEventSeats: Co Seat khong ton tai.', 1;

        -- BR50e/HAI02: Seat hoac Zone da Retired khong duoc dua vao kho ve moi.
        IF EXISTS (
            SELECT 1 FROM @SeatRequests sr
            JOIN   Seat s ON s.SeatID = sr.SeatID
            JOIN   Zone z ON z.ZoneID = s.ZoneID
            WHERE  s.SeatStatus = 'Retired' OR z.ZoneStatus = 'Retired'
        )
            THROW 58219, 'sp_AddEventSeats (BR50e): Co Seat hoac Zone da Retired, khong the dua vao kho ve.', 1;

        -- Mot Venue da bat so do khong duoc co EventSeat nam trong khu chua dat
        -- vi tri. Neu cho phep, trang mua ve chuyen sang renderer SVG va cac ve
        -- nay se bien mat khoi man hinh, du database van con kho hang.
        IF EXISTS (
            SELECT 1
            FROM @SeatRequests sr
            JOIN Seat s  ON s.SeatID = sr.SeatID
            JOIN Zone z  ON z.ZoneID = s.ZoneID
            JOIN Venue v ON v.VenueID = s.VenueID
            WHERE v.MapWidth IS NOT NULL
              AND (z.ZoneX IS NULL OR z.ZoneY IS NULL OR z.ZoneWidth IS NULL OR z.ZoneHeight IS NULL)
        )
            THROW 58220, 'sp_AddEventSeats: Khu cua Seat chua co vi tri tren so do Venue.', 1;

        IF EXISTS (
            SELECT 1 FROM EventSeat es
            JOIN @SeatRequests sr ON sr.SeatID = es.SeatID
            WHERE es.ConcertID = @ConcertID
        )
            THROW 58217, 'sp_AddEventSeats: Co Seat da co trong kho ve cua Concert nay (trung DR-08).', 1;

        -- Insert
        INSERT INTO EventSeat (ConcertID, SeatID, TicketCategoryID, SalePrice, InventoryStatus, AddedTimestamp)
        SELECT @ConcertID, sr.SeatID, @TicketCategoryID, @SalePrice, 'Available', SYSDATETIME()
        FROM @SeatRequests sr;

        DECLARE @Count INT = (SELECT COUNT(*) FROM @SeatRequests);

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'EVENT_SEATS_ADDED', 'Concert', CAST(@ConcertID AS VARCHAR(64)), 'INSERT',
                SYSDATETIME(), '{"SeatCount":' + CAST(@Count AS VARCHAR) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
