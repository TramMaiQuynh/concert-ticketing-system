-- ============================================================
-- sp_CancelConcertMapRevisionDraft (StagePass D.5)
-- Huy mot ConcertMapRevision dang Draft, de Organizer/Admin mo Draft khac
-- (UIX_CMR_OneDraftPerMap chi cho mot Draft/map).
--
-- VI SAO HUY BANG DELETE, KHONG BANG MOT TRANG THAI 'Cancelled':
-- cung nguyen tac da ghi trong sp_DeleteVenueTemplateVersionDraft — Draft chua
-- tung duoc cong bo cho ai, nen no bi HUY THAT, khong "nghi huu". Mot trang thai
-- 'Cancelled' se giu lai vinh vien nhung dong chi tiet (Floor/Object/Section/
-- Seat da snapshot) khong con y nghia, va bat buoc phai sua ca CHK_CMR_Status
-- lan hai filtered unique index. Vet kiem toan da duoc giu bang AuditRecord —
-- do moi la cho dung de luu lich su, khong phai bang nghiep vu.
--
-- VI SAO XOA DUOC AN TOAN (bat bien, da kiem chung):
--   * sp_AddEventSeatsFromMapRevision CHI cho gan EventSeat vao revision dang
--     'Locked' (THROW 60242), nen mot Draft KHONG THE co EventSeat nao tro toi.
--   * Khong bang nao khac tham chieu ConcertMapRevision ngoai
--     ConcertMapRevisionFloor; cac bang con deu tro len bang cha trong noi bo
--     cay nay, va KHONG FK nao co ON DELETE CASCADE — nen phai xoa con truoc.
--   * Mot Draft khong the ton tai dong thoi voi mot revision Locked
--     (sp_CreateConcertMapRevision THROW 60219), va mot Concert co ConcertMap
--     chi mo ban duoc khi da co revision Locked (58061) — nen mot Draft "dang
--     huy duoc" LUON ham y Concert chua mo ban. Vi vay SP nay CO Y khong them
--     kiem tra trang thai Concert: nhanh do khong bao gio toi duoc, va mot
--     nhanh chet chi tao cam giac ve do phu.
--
-- Admin hoac chinh Organizer cua Concert — cung quyen voi
-- sp_CreateConcertMapRevision/sp_LockConcertMapRevision.
-- ============================================================
CREATE OR ALTER PROCEDURE dbo.sp_CancelConcertMapRevisionDraft
(
    @ActorUserID          INT,
    @ConcertMapRevisionID INT
)
AS
BEGIN
    SET NOCOUNT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @ConcertMapID INT,
                @RevisionStatus VARCHAR(32),
                @RevisionNumber INT,
                @SourceVersionID INT,
                @ConcertID INT,
                @OrganizerUserID INT;

        -- UPDLOCK+HOLDLOCK: giu dong revision suot transaction de mot phien khac
        -- khong the Lock dung revision nay ngay giua luc ta dang huy no.
        SELECT @ConcertMapID    = cmr.ConcertMapID,
               @RevisionStatus  = cmr.RevisionStatus,
               @RevisionNumber  = cmr.RevisionNumber,
               @SourceVersionID = cmr.SourceVenueTemplateVersionID
        FROM   ConcertMapRevision cmr WITH (UPDLOCK, HOLDLOCK)
        WHERE  cmr.ConcertMapRevisionID = @ConcertMapRevisionID;

        IF @ConcertMapID IS NULL
            THROW 60231, 'sp_CancelConcertMapRevisionDraft: ConcertMapRevision khong ton tai.', 1;

        SELECT @ConcertID = cm.ConcertID, @OrganizerUserID = c.OrganizerUserID
        FROM   ConcertMap cm
        JOIN   Concert c ON c.ConcertID = cm.ConcertID
        WHERE  cm.ConcertMapID = @ConcertMapID;

        IF NOT (
            @ActorUserID = @OrganizerUserID
            OR EXISTS (SELECT 1 FROM UserRoleAssignment ura JOIN Role r ON r.RoleID = ura.RoleID
                       JOIN UserAccount uaAdm ON uaAdm.UserID = ura.UserID
                       WHERE ura.UserID = @ActorUserID AND r.RoleName = 'Admin'
                         AND ura.AssignmentStatus = 'Active' AND uaAdm.AccountStatus = 'Active')
        )
            THROW 60232, 'sp_CancelConcertMapRevisionDraft: Actor khong co quyen (phai la Organizer cua Concert hoac Admin).', 1;

        -- Revision da Locked la tai lieu cong khai bat bien cua Concert; no khong
        -- the bi huy o day.
        IF @RevisionStatus <> 'Draft'
            THROW 60237, 'sp_CancelConcertMapRevisionDraft: Chi huy duoc revision dang Draft; revision da Locked la ban do dang ban cua Concert.', 1;

        -- Phong thu cho duong GHI TRUC TIEP (app_admin co full DML tren schema —
        -- xem GrantPermissions.sql). TRG_CMRSeat_EventSeatConsistency chi la AFTER
        -- INSERT, UPDATE: no KHONG bat DELETE. Neu mot dong o day da duoc gan
        -- EventSeatID (trai 60242), xoa no se lam hang ton kho do mat vi tri tren
        -- so do — ghe van nam trong kho ve nhung khach khong con thay de chon,
        -- dung loi im lang ma lop trigger sinh ra de chan.
        IF EXISTS (
            SELECT 1
            FROM   ConcertMapRevisionSeat cs
            JOIN   ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID = cs.ConcertMapRevisionSectionID
            JOIN   ConcertMapRevisionFloor   f   ON f.ConcertMapRevisionFloorID     = sec.ConcertMapRevisionFloorID
            WHERE  f.ConcertMapRevisionID = @ConcertMapRevisionID
              AND  cs.EventSeatID IS NOT NULL
        )
            THROW 60238, 'sp_CancelConcertMapRevisionDraft: Revision nay da co ghe duoc dua vao kho ve; khong the huy.', 1;

        -- Xoa ca cay con trong CUNG transaction, dung thu tu FK (khong FK nao co
        -- ON DELETE CASCADE): Seat -> Section -> Object -> Floor -> Revision.
        DELETE cs
        FROM ConcertMapRevisionSeat cs
        JOIN ConcertMapRevisionSection sec ON sec.ConcertMapRevisionSectionID = cs.ConcertMapRevisionSectionID
        JOIN ConcertMapRevisionFloor   f   ON f.ConcertMapRevisionFloorID     = sec.ConcertMapRevisionFloorID
        WHERE f.ConcertMapRevisionID = @ConcertMapRevisionID;

        DELETE sec
        FROM ConcertMapRevisionSection sec
        JOIN ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = sec.ConcertMapRevisionFloorID
        WHERE f.ConcertMapRevisionID = @ConcertMapRevisionID;

        DELETE o
        FROM ConcertMapRevisionObject o
        JOIN ConcertMapRevisionFloor f ON f.ConcertMapRevisionFloorID = o.ConcertMapRevisionFloorID
        WHERE f.ConcertMapRevisionID = @ConcertMapRevisionID;

        DELETE FROM ConcertMapRevisionFloor WHERE ConcertMapRevisionID = @ConcertMapRevisionID;
        DELETE FROM ConcertMapRevision      WHERE ConcertMapRevisionID = @ConcertMapRevisionID;

        -- PreviousValue giu lai phan truy vet CO GIA TRI nhat cua mot dong VUA BI
        -- XOA: ban snapshot tu version nao, thu tu revision trong map, va thuoc
        -- Concert nao. Sau lenh nay khong con bang nghiep vu nao tra loi duoc nua.
        INSERT INTO AuditRecord (ActorUserID, EventType, EntityType, EntityID, Action, EventTimestamp, PreviousValue)
        VALUES (@ActorUserID, 'CONCERT_MAP_REVISION_DRAFT_CANCELLED', 'ConcertMapRevision',
                CAST(@ConcertMapRevisionID AS VARCHAR(64)), 'DELETE', SYSDATETIME(),
                '{"ConcertMapID":' + CAST(@ConcertMapID AS VARCHAR)
                + ',"ConcertID":' + CAST(@ConcertID AS VARCHAR)
                + ',"RevisionNumber":' + CAST(@RevisionNumber AS VARCHAR)
                + ',"SourceVenueTemplateVersionID":' + CAST(@SourceVersionID AS VARCHAR)
                + ',"RevisionStatus":"Draft"}');

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END;
GO