-- ============================================================
-- sp_ConfigureTicketCategory (BP3 / FR12)
-- Them hoac cap nhat Ticket Category cho Concert.
-- Chi Organizer cua Concert hoac Admin.
-- Neu @TicketCategoryID IS NULL -> Tao moi
-- Neu @TicketCategoryID IS NOT NULL -> Cap nhat (BasePrice, Name)
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_ConfigureTicketCategory
(
    @ActorUserID         INT,
    @ConcertID           INT,
    @CategoryName        NVARCHAR(255),
    @CategoryDescription NVARCHAR(500),
    @BasePrice           DECIMAL(18,0),
    @TicketCategoryID    INT = NULL OUTPUT,
    -- FR12/§23.5: SP nay chiu trach nhiem ca Status cua hang ve. Truoc day tham so
    -- nay khong ton tai nen 'Inactive' trong CHK_Category_Status khong the dat toi,
    -- du sp_AddEventSeats doc no de tu choi them ghe vao hang ve da ngung ban (58213).
    -- NULL = giu nguyen (khi cap nhat) / 'Active' (khi tao moi).
    -- Dat o CUOI danh sach de khong lam lech vi tri cua cac caller goi theo thu tu.
    @CategoryStatus      VARCHAR(32) = NULL
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
            THROW 58201, 'sp_ConfigureTicketCategory: Concert khong ton tai.', 1;

        -- Precondition BP3: chi cau hinh hang ve/gia khi Concert o trang thai Draft hoac Published.
        -- Quan trong: cap nhat BasePrice se cascade xuong EventSeat.SalePrice qua
        -- TRG_EventSeatPriceConsistency, nen phai chan khi Concert da SaleClosed/Completed/Cancelled.
        IF @ConcertStatus NOT IN ('Draft', 'Published')
            THROW 58206, 'sp_ConfigureTicketCategory (BP3): Chi cau hinh Ticket Category khi Concert o trang thai Draft hoac Published.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin' AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 58202, 'sp_ConfigureTicketCategory: Actor khong co quyen.', 1;

        IF ISNULL(@CategoryName, '') = ''
            THROW 58203, 'sp_ConfigureTicketCategory: CategoryName khong duoc de trong.', 1;
            
        IF @BasePrice < 0
            THROW 58205, 'sp_ConfigureTicketCategory: BasePrice phai lon hon hoac bang 0.', 1;

        IF @CategoryStatus IS NOT NULL AND @CategoryStatus NOT IN ('Active', 'Inactive')
            THROW 58207, 'sp_ConfigureTicketCategory: CategoryStatus phai la Active hoac Inactive.', 1;

        IF @TicketCategoryID IS NULL OR @TicketCategoryID <= 0
        BEGIN
            -- INSERT
            INSERT INTO TicketCategory (ConcertID, CategoryName, CategoryDescription, CategoryStatus, BasePrice)
            VALUES (@ConcertID, @CategoryName, @CategoryDescription, ISNULL(@CategoryStatus, 'Active'), @BasePrice);

            SET @TicketCategoryID = SCOPE_IDENTITY();

            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TICKET_CATEGORY_CREATED', 'TicketCategory',
                    CAST(@TicketCategoryID AS VARCHAR(64)), 'INSERT', SYSDATETIME(),
                    '{"CategoryName":"' + STRING_ESCAPE(@CategoryName, 'json') + '","BasePrice":' + CAST(@BasePrice AS VARCHAR) + '}');
        END
        ELSE
        BEGIN
            -- UPDATE
            IF NOT EXISTS (SELECT 1 FROM TicketCategory WHERE TicketCategoryID = @TicketCategoryID AND ConcertID = @ConcertID)
                THROW 58204, 'sp_ConfigureTicketCategory: TicketCategoryID khong hop le hoac khong thuoc ve Concert nay.', 1;
                
            -- Khong duoc ngung ban mot hang ve dang co ghe bi giu/da ban: cac Booking
            -- do van con hieu luc va van tro toi hang ve nay.
            IF @CategoryStatus = 'Inactive'
               AND EXISTS (SELECT 1 FROM EventSeat
                           WHERE TicketCategoryID = @TicketCategoryID
                             AND InventoryStatus IN ('OnHold', 'OnHoldForWaitlist', 'Booked'))
                THROW 58208, 'sp_ConfigureTicketCategory: Khong the chuyen hang ve sang Inactive khi con ghe dang duoc giu hoac da ban.', 1;

            UPDATE TicketCategory
            SET CategoryName = @CategoryName,
                CategoryDescription = @CategoryDescription,
                BasePrice = @BasePrice,
                CategoryStatus = COALESCE(@CategoryStatus, CategoryStatus)
            WHERE TicketCategoryID = @TicketCategoryID;
            
            INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, NewValue)
            VALUES (@ActorUserID, 'TICKET_CATEGORY_UPDATED', 'TicketCategory',
                    CAST(@TicketCategoryID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                    '{"CategoryName":"' + STRING_ESCAPE(@CategoryName, 'json') + '","BasePrice":' + CAST(@BasePrice AS VARCHAR) + '}');
        END

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO