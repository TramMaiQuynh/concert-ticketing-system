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
    @SalePrice    DECIMAL(18,0),
    @SeatIDs      NVARCHAR(MAX)   -- CSV: '1,2,3,4'
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @OrganizerUserID INT;
        SELECT @OrganizerUserID = OrganizerUserID FROM Concert WHERE ConcertID = @ConcertID;

        IF @OrganizerUserID IS NULL
            THROW 58211, 'sp_AddEventSeats: Concert khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active')
        )
            THROW 58212, 'sp_AddEventSeats: Actor khong co quyen.', 1;

        IF NOT EXISTS (SELECT 1 FROM TicketCategory
                       WHERE TicketCategoryID = @TicketCategoryID AND ConcertID = @ConcertID AND CategoryStatus = 'Active')
            THROW 58213, 'sp_AddEventSeats: TicketCategory khong thuoc Concert hoac khong Active.', 1;

        IF @SalePrice < 0
            THROW 58214, 'sp_AddEventSeats: SalePrice khong duoc am.', 1;

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