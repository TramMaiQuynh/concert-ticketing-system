-- ============================================================
-- sp_CreateSeatsBatch (FR11a)
-- Tao mot luoi ghe trong MOT giao dich. Day la duong dung cho giao dien "tao
-- hang loat": mot loi ma ghe/vi tri bat ky phai rollback toan bo, khong de lai
-- mot nua so do roi buoc Admin tu kiem dem va don dep thu cong.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CreateSeatsBatch
(
    @ActorUserID INT,
    @ZoneID      INT,
    @SeatsJson   NVARCHAR(MAX)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF NOT EXISTS (
            SELECT 1
            FROM UserRoleAssignment ura
            JOIN Role r ON r.RoleID = ura.RoleID
            JOIN UserAccount ua ON ua.UserID = ura.UserID
            WHERE ura.UserID = @ActorUserID
              AND r.RoleName = 'Admin'
              AND ura.AssignmentStatus = 'Active'
              AND ua.AccountStatus = 'Active'
        )
            THROW 58121, 'sp_CreateSeatsBatch: Chi Admin duoc tao Seat.', 1;

        IF ISJSON(@SeatsJson) <> 1 OR LEFT(LTRIM(@SeatsJson), 1) <> '['
            THROW 59826, 'sp_CreateSeatsBatch: Danh sach ghe phai la JSON hop le.', 1;

        DECLARE @JsonItemCount INT = (SELECT COUNT(*) FROM OPENJSON(@SeatsJson));

        DECLARE @Seats TABLE
        (
            RequestOrder     INT           NOT NULL PRIMARY KEY,
            SeatCode         NVARCHAR(255) NULL,
            SeatLabel        NVARCHAR(500) NULL,
            SeatRowLabel     NVARCHAR(255) NULL,
            SeatColumnNumber INT           NULL
        );

        INSERT INTO @Seats (RequestOrder, SeatCode, SeatLabel, SeatRowLabel, SeatColumnNumber)
        SELECT CONVERT(INT, root.[key]), item.SeatCode, item.SeatLabel,
               item.SeatRowLabel, item.SeatColumnNumber
        FROM OPENJSON(@SeatsJson) root
        CROSS APPLY OPENJSON(root.[value]) WITH
        (
            SeatCode         NVARCHAR(255) '$.seatCode',
            SeatLabel        NVARCHAR(500) '$.seatLabel',
            SeatRowLabel     NVARCHAR(255) '$.seatRowLabel',
            SeatColumnNumber INT           '$.seatColumnNumber'
        ) item;

        DECLARE @SeatCount INT = (SELECT COUNT(*) FROM @Seats);
        IF @SeatCount = 0 OR @SeatCount > 3600 OR @SeatCount <> @JsonItemCount
            THROW 59826, 'sp_CreateSeatsBatch: Danh sach ghe phai co tu 1 den 3600 phan tu.', 1;

        UPDATE @Seats
        SET SeatCode = NULLIF(LTRIM(RTRIM(SeatCode)), ''),
            SeatRowLabel = NULLIF(LTRIM(RTRIM(SeatRowLabel)), '');

        IF EXISTS (SELECT 1 FROM @Seats WHERE NULLIF(LTRIM(RTRIM(SeatCode)), '') IS NULL)
            THROW 58123, 'sp_CreateSeatsBatch: SeatCode khong duoc de trong.', 1;

        IF EXISTS (SELECT 1 FROM @Seats WHERE LEN(SeatCode) > 64 OR LEN(SeatLabel) > 255 OR LEN(SeatRowLabel) > 16)
            THROW 59826, 'sp_CreateSeatsBatch: Mot truong ghe vuot qua do dai cho phep.', 1;

        IF EXISTS (
            SELECT 1 FROM @Seats
            WHERE (SeatRowLabel IS NULL AND SeatColumnNumber IS NOT NULL)
               OR (SeatRowLabel IS NOT NULL AND SeatColumnNumber IS NULL)
        )
            THROW 59821, 'sp_CreateSeatsBatch: Hang va so thu tu trong hang phai di cung nhau.', 1;

        IF EXISTS (SELECT 1 FROM @Seats WHERE SeatColumnNumber <= 0)
            THROW 59822, 'sp_CreateSeatsBatch: So thu tu trong hang phai lon hon 0.', 1;

        IF EXISTS (
            SELECT 1 FROM @Seats
            GROUP BY SeatCode
            HAVING COUNT(*) > 1
        )
            THROW 59827, 'sp_CreateSeatsBatch: Mot ma ghe bi lap trong luoi gui len.', 1;

        IF EXISTS (
            SELECT 1 FROM @Seats
            GROUP BY SeatRowLabel, SeatColumnNumber
            HAVING COUNT(*) > 1
        )
            THROW 59828, 'sp_CreateSeatsBatch: Mot vi tri hang/ghe bi lap trong luoi gui len.', 1;

        DECLARE @VenueID INT, @ZoneStatus VARCHAR(32);
        SELECT @VenueID = VenueID, @ZoneStatus = ZoneStatus
        FROM Zone WITH (UPDLOCK, HOLDLOCK)
        WHERE ZoneID = @ZoneID;

        IF @VenueID IS NULL
            THROW 58122, 'sp_CreateSeatsBatch: Zone khong ton tai.', 1;

        IF @ZoneStatus <> 'Active'
            THROW 59829, 'sp_CreateSeatsBatch: Khong the tao ghe trong Zone da Retired.', 1;

        IF EXISTS (SELECT 1 FROM @Seats WHERE SeatRowLabel IS NULL)
            THROW 59825, 'sp_CreateSeatsBatch: Ghe trong khu co ghe phai co hang va so thu tu trong hang.', 1;

        IF EXISTS (
            SELECT 1
            FROM @Seats r
            JOIN Seat s WITH (UPDLOCK, HOLDLOCK)
              ON s.ZoneID = @ZoneID AND s.SeatCode = CONVERT(VARCHAR(64), r.SeatCode)
        )
            THROW 58124, 'sp_CreateSeatsBatch: Co SeatCode da ton tai trong Zone nay.', 1;

        IF EXISTS (
            SELECT 1
            FROM @Seats r
            JOIN Seat s WITH (UPDLOCK, HOLDLOCK)
              ON s.ZoneID = @ZoneID
             AND s.SeatRowLabel = r.SeatRowLabel
             AND s.SeatColumnNumber = r.SeatColumnNumber
             AND s.SeatStatus = 'Active'
        )
            THROW 59824, 'sp_CreateSeatsBatch: Co vi tri trong luoi da co ghe khac.', 1;

        INSERT INTO Seat (ZoneID, VenueID, SeatCode, SeatLabel, SeatRowLabel, SeatColumnNumber)
        SELECT @ZoneID, @VenueID, CONVERT(VARCHAR(64), SeatCode), CONVERT(NVARCHAR(255), SeatLabel),
               CONVERT(NVARCHAR(16), SeatRowLabel), SeatColumnNumber
        FROM @Seats
        ORDER BY RequestOrder;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
        VALUES (@ActorUserID, 'SEATS_BATCH_CREATED', 'Zone', CAST(@ZoneID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                '{"SeatCount":' + CAST(@SeatCount AS VARCHAR(12)) + '}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
