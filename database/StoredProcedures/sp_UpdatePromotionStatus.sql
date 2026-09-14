-- ============================================================
-- sp_UpdatePromotionStatus (BP13 / FR52)
-- Chuyen PromotionStatus giua Draft / Active / Disabled.
-- Quyen: Organizer so huu Concert cua Promotion hoac Admin.
--
-- Ly do SP nay ton tai (§24.4): PromotionStatus co domain nhieu gia tri nhung
-- sp_CreatePromotion chi ghi 'Active' luc INSERT va khong SP nao doi duoc no.
-- Nghia la Organizer khong the soan mot chuong trinh o trang thai nhap
-- ('Draft') truoc khi cong bo, cung khong the tat khan cap mot chuong trinh
-- dang chay ('Disabled') khi phat hien cau hinh sai - hai thao tac van hanh
-- co ban nhat cua bat ky he thong khuyen mai nao.
--
-- LUU Y VE 'Expired': gia tri nay da bi loai khoi domain. Het han la thuoc tinh
-- DAN XUAT tu EndDatetime, khong phai trang thai luu tru; giu ca hai se tao ra
-- hai nguon su that mau thuan nhau (BR50d) - vi du PromotionStatus='Active'
-- nhung da qua EndDatetime, hoac nguoc lai. Hieu luc theo thoi gian duoc quyet
-- dinh mot noi duy nhat: khoang nua mo [StartDatetime, EndDatetime).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdatePromotionStatus
(
    @ActorUserID INT,
    @PromotionID INT,
    @NewStatus   VARCHAR(32)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @NewStatus NOT IN ('Draft', 'Active', 'Disabled')
            THROW 59601, 'sp_UpdatePromotionStatus: PromotionStatus phai la Draft, Active hoac Disabled.', 1;

        DECLARE @OldStatus VARCHAR(32), @OrganizerUserID INT;
        SELECT @OldStatus       = p.PromotionStatus,
               @OrganizerUserID = c.OrganizerUserID
        FROM   Promotion p WITH (UPDLOCK)
        JOIN   Concert   c ON c.ConcertID = p.ConcertID
        WHERE  p.PromotionID = @PromotionID;

        IF @OldStatus IS NULL
            THROW 59602, 'sp_UpdatePromotionStatus: Promotion khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin'
                         AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 59603, 'sp_UpdatePromotionStatus: Actor khong co quyen.', 1;

        -- Khong quay lai 'Draft' sau khi da cong bo: cac Booking da ap dung chuong
        -- trinh nay se tro toi mot chuong trinh "chua cong bo", lam ho so gia sai lech.
        -- Muon dung phat hanh thi dung 'Disabled' - vua dung ngay, vua giu lich su.
        IF @NewStatus = 'Draft' AND @OldStatus <> 'Draft'
            THROW 59604, 'sp_UpdatePromotionStatus: Khong the dua Promotion da cong bo tro lai Draft - dung Disabled de ngung phat hanh.', 1;

        -- Bat mot Promotion khong duoc lam bat kem theo mot ma dang trung voi Promotion
        -- Active khac cua cung Concert: khi ay khach go ma do se roi vao hai chuong trinh
        -- cung luc va he thong khong chon duoc (xem sp_CreateDiscountCode, 58604).
        IF @NewStatus = 'Active' AND EXISTS (
            SELECT 1
            FROM   DiscountCode dcMine
            JOIN   DiscountCode dcOther ON dcOther.CodeValue      = dcMine.CodeValue
                                       AND dcOther.DiscountCodeID <> dcMine.DiscountCodeID
                                       AND dcOther.CodeStatus      = 'Active'
            JOIN   Promotion    pOther  ON pOther.PromotionID      = dcOther.PromotionID
                                       AND pOther.PromotionStatus  = 'Active'
            WHERE  dcMine.PromotionID = @PromotionID
              AND  dcMine.CodeStatus  = 'Active'
              AND  pOther.ConcertID   = (SELECT ConcertID FROM Promotion WHERE PromotionID = @PromotionID)
        )
            THROW 59605, 'sp_UpdatePromotionStatus: Promotion nay co ma trung voi mot Promotion Active khac cua cung Concert.', 1;

        UPDATE Promotion SET PromotionStatus = @NewStatus WHERE PromotionID = @PromotionID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'PROMOTION_STATUS_CHANGED', 'Promotion',
                CAST(@PromotionID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"PromotionStatus":"' + @OldStatus + '"}',
                '{"PromotionStatus":"' + @NewStatus + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
