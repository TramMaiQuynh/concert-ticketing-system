-- ============================================================================
-- TRG_FiringOrder.sql -- GHIM THU TU KHAI HOA CUA CAC AFTER TRIGGER
-- ============================================================================
--
-- VAN DE
-- ------
-- SQL Server KHONG dam bao thu tu chay giua nhieu AFTER trigger cung dinh nghia
-- tren mot (bang, hanh dong). Thu tu thuc te phu thuoc vao thu tu tao doi tuong
-- va co the doi sau moi lan deploy sach hoac sau moi lan CREATE OR ALTER.
--
-- Voi trigger chi KIEM TRA roi THROW, dieu do co nghia: mot thao tac vi pham
-- DONG THOI hai quy tac se tra ve MA LOI KHAC NHAU giua cac lan deploy. Vi tang
-- API anh xa ma loi SQL sang ma HTTP va thong diep nguoi dung, cung mot hanh vi
-- sai cua nguoi dung se nhan hai phan hoi khac nhau -- va cac test hoi quy khang
-- dinh mot ma loi cu the se xanh o lan chay nay, do o lan deploy ke tiep.
--
-- Loi nay DA bieu hien that tren bang Seat (50131 vs 50120) va da lam mot test
-- hoi quy dao dong giua hai lan deploy. Day khong phai suy dien.
--
-- QUY TAC CHON TRIGGER CHAY TRUOC
-- -------------------------------
-- 1. Neu bang co trigger may trang thai (*_StateTransition) -> ghim no chay TRUOC.
--    Ly do: cau hoi "phep chuyen trang thai nay co hop le khong" la cau hoi CO BAN
--    nhat ve mot dong du lieu. Neu phep chuyen da sai thi moi kiem tra toan ven
--    chi tiet hon deu la he qua, khong phai nguyen nhan. Bao dung nguyen nhan goc
--    la thong tin huu ich nhat cho ca nguoi dung lan nguoi van hanh.
-- 2. Neu bang khong co trigger may trang thai -> ghim trigger phat bieu rang buoc
--    CO CAU (thuoc ve dung thuc the cha, dung danh tinh) chay truoc trigger phat
--    bieu rang buoc TRANG THAI / SO LUONG.
--
-- Muc tieu o day la TINH XAC DINH, khong phai toi uu hoa. Mot thu tu co dinh va
-- duoc giai thich thi kiem thu duoc; thu tu tuy y thi khong.
--
-- VI SAO LA MOT FILE RIENG, CHAY CUOI PHASE 4
-- -------------------------------------------
-- sp_settriggerorder yeu cau trigger DA TON TAI. Quan trong hon: CREATE OR ALTER
-- TRIGGER RESET thu tu da ghim ve NULL. Vi vay viec ghim phai la thao tac CUOI
-- CUNG sau khi moi trigger da duoc tao.
--
-- => Neu deploy lai RIENG mot file trigger nao do, PHAI chay lai file nay.
-- ============================================================================

SET NOCOUNT ON;
GO

DECLARE @Priority TABLE (
    TriggerName SYSNAME       NOT NULL PRIMARY KEY,
    Rationale   VARCHAR(200)  NOT NULL
);

-- (1) Trigger may trang thai -- chay truoc tren chinh bang cua no.
INSERT INTO @Priority (TriggerName, Rationale) VALUES
    (N'TRG_Concert_StateTransition',       'Phep chuyen trang thai Concert la kiem tra co ban nhat'),
    (N'TRG_EventSeat_StateTransition',     'Phep chuyen trang thai ton kho ghe la kiem tra co ban nhat'),
    (N'TRG_Booking_StateTransition',       'Phep chuyen trang thai Booking la kiem tra co ban nhat'),
    (N'TRG_Payment_StateTransition',       'Phep chuyen trang thai Payment la kiem tra co ban nhat'),
    (N'TRG_Ticket_StateTransition',        'Phep chuyen trang thai Ticket la kiem tra co ban nhat'),
    (N'TRG_Refund_StateTransition',        'Phep chuyen trang thai Refund la kiem tra co ban nhat'),
    (N'TRG_Waitlist_StateTransition',      'Phep chuyen trang thai Waitlist la kiem tra co ban nhat'),
    (N'TRG_WaitlistEntry_StateTransition', 'Phep chuyen trang thai WaitlistEntry la kiem tra co ban nhat'),
    (N'TRG_Queue_StateTransition',         'Phep chuyen trang thai Queue la kiem tra co ban nhat'),
    (N'TRG_QueueEntry_StateTransition',    'Phep chuyen trang thai QueueEntry la kiem tra co ban nhat');

-- (2) Bang khong co trigger may trang thai -- chon theo quy tac "co cau truoc trang thai".
INSERT INTO @Priority (TriggerName, Rationale) VALUES
    -- Seat: guard noi RO nguyen nhan (ghe dang nam trong kho ve cua mot concert) va
    -- viec phai lam; TRG_SeatVenueConsistency chi phat bieu lai bat bien o muc thap hon.
    (N'TRG_SeatVenueChangeGuard',      'Thong bao neu ro nguyen nhan va cach xu ly'),
    -- BookingEventSeatAllocation: "ghe nay co thuoc dung concert cua booking khong"
    -- la cau hoi ve DANH TINH, dung truoc cau hoi ve trang thai ton kho.
    (N'TRG_AllocationConcert',         'Rang buoc co cau dung truoc rang buoc trang thai ton kho'),
    -- BookingPromotionApplication: khuyen mai con hieu luc hay khong la dieu kien tien
    -- quyet; yeu cau kem ma giam gia chi co nghia khi khuyen mai con hieu luc.
    (N'TRG_PromotionValidity',         'Hieu luc khuyen mai la dieu kien tien quyet'),
    -- AuditRecord: "phien nay la ai" dung truoc "ban ghi nay co hop le khong".
    (N'TRG_AuditRecord_SecurityGuard', 'Kiem tra danh tinh phien dung truoc kiem tra noi dung');

-- ---------------------------------------------------------------------------
-- Ghim: voi moi trigger uu tien, dat @order='First' cho DUNG nhung hanh dong ma
-- no thuc su xu ly (doc tu sys.trigger_events, khong phong doan).
-- ---------------------------------------------------------------------------
DECLARE @trg SYSNAME, @stmt NVARCHAR(10), @n INT = 0;

DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT tr.name, te.type_desc
    FROM   sys.triggers tr
    JOIN   sys.trigger_events te ON te.object_id = tr.object_id
    JOIN   @Priority p           ON p.TriggerName = tr.name
    WHERE  tr.is_disabled = 0
      AND  tr.is_instead_of_trigger = 0   -- sp_settriggerorder chi ap dung cho AFTER trigger
      AND  te.type_desc IN ('INSERT', 'UPDATE', 'DELETE')
    ORDER BY tr.name, te.type_desc;

OPEN cur;
FETCH NEXT FROM cur INTO @trg, @stmt;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC sp_settriggerorder @triggername = @trg,
                            @order       = N'First',
                            @stmttype    = @stmt;
    SET @n += 1;
    FETCH NEXT FROM cur INTO @trg, @stmt;
END
CLOSE cur;
DEALLOCATE cur;

PRINT N'TRG_FiringOrder: da ghim ' + CAST(@n AS VARCHAR(10)) + N' cap (trigger, hanh dong).';
GO

-- ---------------------------------------------------------------------------
-- KIEM CHUNG: moi to hop (bang, hanh dong) co NHIEU HON MOT AFTER trigger deu
-- phai co dung mot trigger duoc ghim First. Con to hop chua ghim -> bao loi ngay
-- luc deploy, thay vi de no bieu hien thanh test dao dong ve sau.
-- ---------------------------------------------------------------------------
;WITH t AS (
    -- COLLATE DATABASE_DEFAULT o ca hai cot: OBJECT_NAME() tra ve collation cua
    -- database con te.type_desc mang collation cua catalog. Noi hai chuoi khac
    -- collation trong STRING_AGG ben duoi se loi 4191. Khong ep collation thi
    -- chinh DUONG BAO LOI bi hong -- da kiem chung bang cach go ghim mot trigger.
    SELECT OBJECT_NAME(tr.parent_id) COLLATE DATABASE_DEFAULT AS TableName,
           te.type_desc              COLLATE DATABASE_DEFAULT AS Act,
           CASE te.type_desc
               WHEN 'INSERT' THEN OBJECTPROPERTY(tr.object_id, 'ExecIsFirstInsertTrigger')
               WHEN 'UPDATE' THEN OBJECTPROPERTY(tr.object_id, 'ExecIsFirstUpdateTrigger')
               ELSE               OBJECTPROPERTY(tr.object_id, 'ExecIsFirstDeleteTrigger')
           END                       AS IsFirst
    FROM   sys.triggers tr
    JOIN   sys.trigger_events te ON te.object_id = tr.object_id
    WHERE  tr.is_ms_shipped = 0
      AND  tr.parent_class = 1
      AND  tr.is_instead_of_trigger = 0
      AND  te.type_desc IN ('INSERT', 'UPDATE', 'DELETE')
)
SELECT TableName, Act, COUNT(*) AS SoTrigger
INTO   #ChuaGhim
FROM   t
GROUP BY TableName, Act
HAVING COUNT(*) > 1 AND SUM(IsFirst) = 0;

IF EXISTS (SELECT 1 FROM #ChuaGhim)
BEGIN
    DECLARE @ds NVARCHAR(MAX) =
        (SELECT STRING_AGG(TableName + '/' + Act, ', ') FROM #ChuaGhim);
    RAISERROR (N'TRG_FiringOrder: con to hop nhieu trigger CHUA ghim thu tu: %s. Bo sung vao @Priority.',
               16, 1, @ds);
END
ELSE
    PRINT N'TRG_FiringOrder: moi to hop nhieu trigger deu da co thu tu xac dinh.';

DROP TABLE #ChuaGhim;
GO
