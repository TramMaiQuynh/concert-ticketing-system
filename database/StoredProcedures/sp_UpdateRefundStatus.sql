-- ============================================================
-- sp_UpdateRefundStatus (BP8 / BR32 / §10.1 / §24.4)
-- Ket thuc mot yeu cau hoan tien MA KHONG chi tra: Pending -> Failed | Cancelled.
--
-- Ly do SP nay ton tai:
-- §10.1 dinh nghia ro hai trang thai nay va khai bao Pending -> Confirmed/Failed/
-- Cancelled la ba dich HOP LE. Trigger TRG_Refund_StateTransition da cho phep ca ba,
-- va TRG_RefundLimits da CO Y loai Failed/Cancelled ra khoi tong hoan tien - tuc toan
-- bo ha tang cho hai trang thai nay da san sang tu dau. Nhung truoc day KHONG co bat
-- ky duong ghi nao dat duoc chung: sp_ConfirmRefund chi dat 'Confirmed' va khong nhan
-- tham so trang thai; nam lenh INSERT deu dat cung 'Pending'. Mot gia tri domain
-- khong co ben ghi thi khong phai trang thai, chi la chu chet (§24.4).
--
-- HAU QUA THAT cua viec thieu duong ghi (day la ly do nghiep vu, khong phai ly do
-- hinh thuc): khi cong thanh toan TU CHOI mot khoan hoan, he thong khong co cach nao
-- ghi nhan. Khoan do nam 'Pending' vinh vien, hang doi hoan tien cua ban to chuc tich
-- tu nhung muc khong bao gio dong lai duoc, va khong gi phan biet duoc "dang cho
-- settle" voi "da that bai". Chinh sp_ConfirmRefund cung co mot nhanh guard danh cho
-- Failed/Cancelled ma khong du lieu nao cham toi duoc.
--
-- VI SAO MOT SP CHO CA HAI TRANG THAI, khong phai hai SP rieng:
-- Hai chuyen doi nay co CUNG co che (ket thuc yeu cau, khong dong den tien) va trong
-- he thong nay deu do NGUOI VAN HANH thuc hien - khong co callback hoan tien tu cong
-- thanh toan. Quy uoc san co cua du an cho thao tac doi trang thai kieu nay la mot SP
-- nhan tham so trang thai: sp_UpdatePromotionStatus, sp_UpdateDiscountCodeStatus,
-- sp_AdminUpdateUserStatus, sp_UpdateRoleStatus. Tach lam hai SP se nhan doi phan
-- kiem quyen va ghi audit ma khong them y nghia nao.
--
-- TUYET DOI KHONG dong den Payment.PaymentStatus: khong dong nao roi tai khoan thu,
-- nen Payment phai giu nguyen 'Confirmed'/'PartiallyRefunded'. Chuyen Payment sang
-- PartiallyRefunded/Refunded la doc quyen cua sp_ConfirmRefund, va chi khi khoan hoan
-- thuc su duoc settle (BR32b).
--
-- Ly do @Reason di vao AuditRecord chu khong vao Refund.RefundReason:
-- RefundReason la ly do KHACH duoc hoan tien (do sp_ProcessRefund ghi luc tao yeu
-- cau). Ly do TU CHOI hay THAT BAI la mot su kien khac, xay ra sau, do mot actor khac
-- thuc hien - ghi de len RefundReason se lam mat thong tin goc va tron lan hai nghia
-- vao mot cot. Su kien thuoc ve nhat ky kiem toan (§12.17).
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_UpdateRefundStatus
(
    @ActorUserID INT,
    @RefundID    INT,
    @NewStatus   VARCHAR(32),
    @Reason      NVARCHAR(500)
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Mien gia tri: SP nay CHI dung cho hai ket cuc khong chi tra.
        --    'Confirmed' co duong rieng (sp_ConfirmRefund) vi no keo theo viec cap
        --    nhat Payment; 'Pending' la trang thai khoi tao, khong quay lai duoc.
        IF @NewStatus NOT IN ('Failed', 'Cancelled')
            THROW 59911, 'sp_UpdateRefundStatus: NewStatus phai la Failed hoac Cancelled. Muon xac nhan da hoan tien thi dung sp_ConfirmRefund.', 1;

        IF @Reason IS NULL OR LTRIM(RTRIM(@Reason)) = ''
            THROW 59912, 'sp_UpdateRefundStatus: Phai ghi ly do - day la thao tac ket thuc mot yeu cau hoan tien ma khong tra tien cho khach.', 1;

        -- 2. Refund phai ton tai. UPDLOCK de tuan tu hoa voi sp_ConfirmRefund chay
        --    dong thoi tren cung khoan hoan (webhook settle den cung luc nguoi van
        --    hanh bam tu choi).
        DECLARE @PaymentID INT, @OldStatus VARCHAR(32);
        SELECT @PaymentID = PaymentID, @OldStatus = RefundStatus
        FROM   Refund WITH (UPDLOCK)
        WHERE  RefundID = @RefundID;

        IF @PaymentID IS NULL
            THROW 59913, 'sp_UpdateRefundStatus: Refund khong ton tai.', 1;

        -- 3. Idempotent: goi lai dung trang thai da co khong phai loi. Dong bo voi
        --    cach sp_ConfirmRefund va sp_FailPayment xu ly webhook gui lap (BR49a).
        IF @OldStatus = @NewStatus
        BEGIN
            COMMIT TRANSACTION;
            RETURN;
        END

        -- 4. Chi ket thuc duoc mot yeu cau DANG CHO. 'Confirmed' la terminal va tien
        --    da roi tai khoan thu - danh dau no la Failed se noi doi ve dong tien.
        IF @OldStatus <> 'Pending'
            THROW 59914, 'sp_UpdateRefundStatus: Chi ket thuc duoc khoan hoan dang Pending.', 1;

        -- 5. Quyen: Admin, hoac Organizer so huu Concert cua Booking chua Payment nay.
        --    Cung khuon voi sp_ConfirmRefund.
        DECLARE @ConcertOrg INT;
        SELECT @ConcertOrg = c.OrganizerUserID
        FROM   Payment p
        JOIN   Booking b ON b.BookingID = p.BookingID
        JOIN   Concert c ON c.ConcertID = b.ConcertID
        WHERE  p.PaymentID = @PaymentID;

        IF NOT (
            @ActorUserID = @ConcertOrg
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura
                       JOIN   Role r ON r.RoleID = ura.RoleID
                       JOIN   UserAccount ua ON ua.UserID = ura.UserID
                       WHERE  ura.UserID = @ActorUserID
                         AND  r.RoleName = 'Admin'
                         AND  ura.AssignmentStatus = 'Active'
                         AND  ua.AccountStatus = 'Active')
        )
            THROW 59915, 'sp_UpdateRefundStatus: Actor khong co quyen.', 1;

        -- 6. Chuyen trang thai. RefundConfirmationTimestamp GIU NGUYEN NULL: khong co
        --    khoan settle nao xay ra. RefundReason giu nguyen ly do hoan tien goc.
        UPDATE Refund
        SET    RefundStatus = @NewStatus
        WHERE  RefundID = @RefundID
          AND  RefundStatus = 'Pending';   -- conditional: chan race voi sp_ConfirmRefund

        IF @@ROWCOUNT = 0
            THROW 59914, 'sp_UpdateRefundStatus: Chi ket thuc duoc khoan hoan dang Pending.', 1;

        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue, NewValue)
        VALUES (@ActorUserID,
                CASE WHEN @NewStatus = 'Failed' THEN 'REFUND_FAILED' ELSE 'REFUND_CANCELLED' END,
                'Refund', CAST(@RefundID AS VARCHAR(64)), 'UPDATE', SYSDATETIME(),
                '{"RefundStatus":"' + @OldStatus + '"}',
                '{"RefundStatus":"' + @NewStatus + '","Reason":"' + STRING_ESCAPE(@Reason, 'json') + '"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO
