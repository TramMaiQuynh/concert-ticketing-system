-- ============================================================
-- sp_UpdateDiscountCodeStatus (BP13 / FR53b)
-- Chuyen CodeStatus giua Active / Disabled.
-- Quyen: Organizer so huu Concert cua Promotion hoac Admin.
--
-- Ly do SP nay ton tai (§24.4): CodeStatus chi duoc ghi 'Active' luc INSERT trong
-- sp_CreateDiscountCode va khong SP nao doi duoc. Trong khi do sp_ApplyPromotion
-- (54009) va TRG_PromotionValidity (50091) deu tu choi ma co CodeStatus <> 'Active'
-- - tuc la ca hai lop bao ve deu doi mot trang thai ma khong ai tao ra duoc.
-- Hau qua thuc te: mot ma giam gia bi ro ri ra ngoai KHONG CO cach nao thu hoi
-- trong khi no van con trong khoang ValidFrom/ValidTo.
--
-- LUU Y VE 'Expired': da bi loai khoi domain vi trung lap voi ValidToDatetime
-- (cung ly do nhu PromotionStatus - xem sp_UpdatePromotionStatus).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateDiscountCodeStatus
(
    @ActorUserID    INT,
    @DiscountCodeID INT,
    @NewStatus      VARCHAR(32)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @NewStatus NOT IN ('Active', 'Disabled')
            THROW 59611, 'sp_UpdateDiscountCodeStatus: CodeStatus phai la Active hoac Disabled.', 1;

        DECLARE @OldStatus VARCHAR(32), @OrganizerUserID INT;
        SELECT @OldStatus       = dc.CodeStatus,
               @OrganizerUserID = c.OrganizerUserID
        FROM   DiscountCode dc WITH (UPDLOCK)
        JOIN   Promotion    p  ON p.PromotionID = dc.PromotionID
        JOIN   Concert      c  ON c.ConcertID   = p.ConcertID
        WHERE  dc.DiscountCodeID = @DiscountCodeID;

        IF @OldStatus IS NULL
            THROW 59612, 'sp_UpdateDiscountCodeStatus: DiscountCode khong ton tai.', 1;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin'
                         AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 59613, 'sp_UpdateDiscountCodeStatus: Actor khong co quyen.', 1;

        UPDATE DiscountCode SET CodeStatus = @NewStatus WHERE DiscountCodeID = @DiscountCodeID;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID, 'DISCOUNT_CODE_STATUS_CHANGED', 'DiscountCode',
                CAST(@DiscountCodeID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"CodeStatus":"' + @OldStatus + '"}',
                '{"CodeStatus":"' + @NewStatus + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
