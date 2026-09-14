-- ============================================================
-- sp_AddEventSeatsFromMapRevision (StagePass D.5 -> BP3/FR11)
--
-- Cau noi con thieu duoc ghi lai trong chinh comment cua
-- ConcertMapRevisionSeat.sql: "SP thay the sp_AddEventSeats se gan cot
-- [EventSeatID] nay". Day la SP do. sp_AddEventSeats (Zone/Seat) van con
-- nguyen, khong bi thay the — day la mot DUONG THU HAI dua Seat vao kho ve,
-- xuat phat tu mot ConcertMapRevision da Locked thay vi tu danh sach SeatID
-- go tay theo Zone.
--
-- CHI duoc dua ghe tu revision dang LOCKED: comment sp_LockConcertMapRevision.sql
-- da ghi ro "tu day la revision DUY NHAT API cong khai doc de ban" — Draft la
-- ban dang soan, chua phai so do that, dua ghe tu Draft vao kho ve se ban
-- nhung cho ngoi co the bi xoa/doi truoc khi Lock.
--
-- Moi buoc kiem tra day theo dung khuon sp_AddEventSeats (BP3, TicketCategory
-- Active, BR50e Retired, DR-08 trung Seat-Concert) — chi khac nguon dau vao la
-- ConcertMapRevisionSeatID thay vi SeatID tho, va them mot buoc GHI NGUOC
-- EventSeatID vao ConcertMapRevisionSeat sau khi tao EventSeat, de tu do ve
-- sau truy van doc (GetStagePassSeatMapAsync) biet ghe nao da mo ban.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_AddEventSeatsFromMapRevision
(
    @ActorUserID               INT,
    @ConcertMapRevisionID      INT,
    @TicketCategoryID          INT,
    @ConcertMapRevisionSeatIDs NVARCHAR(MAX)   -- CSV: '1,2,3,4'
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Khoa dong revision truoc (cung khuon sp_LockConcertMapRevision) de tuan
        -- tu hoa cac lan them ghe canh tranh cho CUNG revision.
        DECLARE @ConcertMapID INT, @RevisionStatus VARCHAR(32);
        SELECT @ConcertMapID = ConcertMapID, @RevisionStatus = RevisionStatus
        FROM ConcertMapRevision WITH (UPDLOCK, HOLDLOCK)
        WHERE ConcertMapRevisionID = @ConcertMapRevisionID;

        IF @ConcertMapID IS NULL
            THROW 60241, 'sp_AddEventSeatsFromMapRevision: ConcertMapRevision khong ton tai.', 1;

        IF @RevisionStatus <> 'Locked'
            THROW 60242, 'sp_AddEventSeatsFromMapRevision: Chi duoc dua ghe vao kho ve tu revision dang Locked.', 1;

        DECLARE @ConcertID INT, @OrganizerUserID INT, @ConcertStatus VARCHAR(32);
        SELECT @ConcertID = cm.ConcertID, @OrganizerUserID = c.OrganizerUserID, @ConcertStatus = c.ConcertStatus
        FROM ConcertMap cm JOIN Concert c ON c.ConcertID = cm.ConcertID
        WHERE cm.ConcertMapID = @ConcertMapID;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 60243, 'sp_AddEventSeatsFromMapRevision: Actor khong co quyen (phai la Organizer cua Concert hoac Admin).', 1;

        -- BP3, cung khuon sp_AddEventSeats.
        IF @ConcertStatus NOT IN ('Draft', 'Published')
            THROW 60244, 'sp_AddEventSeatsFromMapRevision (BP3): Chi them EventSeat khi Concert o trang thai Draft hoac Published.', 1;

        DECLARE @SalePrice DECIMAL(18,0);
        SELECT @SalePrice = BasePrice
        FROM TicketCategory
        WHERE TicketCategoryID = @TicketCategoryID AND ConcertID = @ConcertID AND CategoryStatus = 'Active';

        IF @SalePrice IS NULL
            THROW 60245, 'sp_AddEventSeatsFromMapRevision: TicketCategory khong thuoc Concert hoac khong Active.', 1;

        -- Parse CSV — TRY_CONVERT thay vi CAST tho, cung ly do da sua o
        -- sp_AddEventSeats.sql (mot phan tu khong phai so tra ve loi nghiep vu
        -- ro rang thay vi loi chuyen doi SQL tho).
        IF EXISTS (
            SELECT 1 FROM STRING_SPLIT(@ConcertMapRevisionSeatIDs, ',')
            WHERE LTRIM(RTRIM(value)) <> '' AND TRY_CONVERT(INT, value) IS NULL
        )
            THROW 60251, 'sp_AddEventSeatsFromMapRevision: Danh sach ghe chua gia tri khong phai so nguyen.', 1;

        DECLARE @Requests TABLE (ConcertMapRevisionSeatID INT NOT NULL PRIMARY KEY);
        INSERT INTO @Requests (ConcertMapRevisionSeatID)
        SELECT DISTINCT TRY_CONVERT(INT, value)
        FROM STRING_SPLIT(@ConcertMapRevisionSeatIDs, ',')
        WHERE LTRIM(RTRIM(value)) <> '';

        IF NOT EXISTS (SELECT 1 FROM @Requests)
            THROW 60246, 'sp_AddEventSeatsFromMapRevision: Danh sach ghe rong.', 1;

        -- Khoa cac dong ConcertMapRevisionSeat lien quan, dong thoi xac nhan CHUNG
        -- thuoc dung revision nay (khong nhan nham ghe cua mot revision/concert khac
        -- chi vi trung ConcertMapRevisionSeatID — id nay khong tu than mang tinh bao mat).
        DECLARE @Seats TABLE (ConcertMapRevisionSeatID INT PRIMARY KEY, SeatID INT NOT NULL, EventSeatID INT NULL);
        INSERT INTO @Seats (ConcertMapRevisionSeatID, SeatID, EventSeatID)
        SELECT cmrs.ConcertMapRevisionSeatID, cmrs.SeatID, cmrs.EventSeatID
        FROM ConcertMapRevisionSeat cmrs WITH (UPDLOCK, HOLDLOCK)
        JOIN ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID = cmrs.ConcertMapRevisionSectionID
        JOIN ConcertMapRevisionFloor   flr ON flr.ConcertMapRevisionFloorID   = sec.ConcertMapRevisionFloorID
        JOIN @Requests req ON req.ConcertMapRevisionSeatID = cmrs.ConcertMapRevisionSeatID
        WHERE flr.ConcertMapRevisionID = @ConcertMapRevisionID;

        IF (SELECT COUNT(*) FROM @Seats) <> (SELECT COUNT(*) FROM @Requests)
            THROW 60247, 'sp_AddEventSeatsFromMapRevision: Co ghe khong thuoc revision nay.', 1;

        IF EXISTS (SELECT 1 FROM @Seats WHERE EventSeatID IS NOT NULL)
            THROW 60248, 'sp_AddEventSeatsFromMapRevision: Co ghe da duoc dua vao kho ve tu truoc (trung).', 1;

        -- BR50e, cung khuon sp_AddEventSeats.
        IF EXISTS (
            SELECT 1 FROM @Seats sv
            JOIN Seat s ON s.SeatID = sv.SeatID
            JOIN Zone z ON z.ZoneID = s.ZoneID
            WHERE s.SeatStatus = 'Retired' OR z.ZoneStatus = 'Retired'
        )
            THROW 60249, 'sp_AddEventSeatsFromMapRevision (BR50e): Co Seat hoac Zone da Retired, khong the dua vao kho ve.', 1;

        -- DR-08: Seat da co trong kho ve cua CHINH Concert nay tu nguon khac (vd da
        -- them qua sp_AddEventSeats/Zone truoc khi dung StagePass cho cung Concert).
        -- UQ_EventSeat_Concert_Seat se chan o buoc INSERT, nhung kiem tra som de tra
        -- ve loi ro rang thay vi mot loi constraint tho.
        IF EXISTS (
            SELECT 1 FROM EventSeat es
            JOIN @Seats sv ON sv.SeatID = es.SeatID
            WHERE es.ConcertID = @ConcertID
        )
            THROW 60250, 'sp_AddEventSeatsFromMapRevision: Co Seat da co trong kho ve cua Concert nay (trung DR-08).', 1;

        DECLARE @Inserted TABLE (SeatID INT NOT NULL, EventSeatID INT NOT NULL);

        INSERT INTO EventSeat (ConcertID, SeatID, TicketCategoryID, SalePrice, InventoryStatus, AddedTimestamp)
        OUTPUT inserted.SeatID, inserted.EventSeatID INTO @Inserted (SeatID, EventSeatID)
        SELECT @ConcertID, sv.SeatID, @TicketCategoryID, @SalePrice, 'Available', SYSDATETIME()
        FROM @Seats sv;

        -- Ghi nguoc EventSeatID vao ConcertMapRevisionSeat — day chinh la cau noi
        -- ma comment ConcertMapRevisionSeat.sql da hua.
        UPDATE cmrs
        SET cmrs.EventSeatID = ins.EventSeatID
        FROM ConcertMapRevisionSeat cmrs
        JOIN @Seats sv ON sv.ConcertMapRevisionSeatID = cmrs.ConcertMapRevisionSeatID
        JOIN @Inserted ins ON ins.SeatID = sv.SeatID;

        DECLARE @Count INT = (SELECT COUNT(*) FROM @Seats);

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'EVENT_SEATS_ADDED_FROM_MAP_REVISION', 'ConcertMapRevision', CAST(@ConcertMapRevisionID AS VARCHAR(64)), 'INSERT',
                SYSDATETIME(), '{"SeatCount":' + CAST(@Count AS VARCHAR) + ',"ConcertID":' + CAST(@ConcertID AS VARCHAR) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
