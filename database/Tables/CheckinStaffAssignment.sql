CREATE TABLE CheckinStaffAssignment (
    UserID INT NOT NULL,
    ConcertID INT NOT NULL,
    -- BR39a dat ten dung bon thanh phan cua ban ghi phan cong:
    -- (staff_user_id, concert_id, assigned_by, assigned_at). AssignedByUserID la
    -- thanh phan thu ba - AI da cap quyen nay.
    --
    -- Vi sao khong de AuditRecord ganh: audit la NHAT KY SU KIEN, con day la
    -- TRANG THAI HIEN HANH cua mot quyen dang co hieu luc. AuditRecord.EntityID la
    -- tham chieu da hinh khong co FK nen khong join an toan duoc; bang audit lai la
    -- bang lon nhanh nhat he thong va se bi archive - luc do cau hoi "ai cap quyen
    -- nay" mat cau tra loi. Moi he IAM thuc te (Okta, Auth0, AWS IAM) deu dat
    -- granted_by ngay tren ban ghi grant.
    AssignedByUserID INT NOT NULL,
    AssignedTimestamp DATETIME2(7) NOT NULL DEFAULT SYSDATETIME(),
    AssignmentStatus VARCHAR(32) NOT NULL DEFAULT 'Active',
    CONSTRAINT PK_CheckinStaffAssignment PRIMARY KEY CLUSTERED (UserID, ConcertID),
    CONSTRAINT FK_CheckinStaffAssignment_User FOREIGN KEY (UserID) REFERENCES UserAccount(UserID),
    CONSTRAINT FK_CheckinStaffAssignment_Concert FOREIGN KEY (ConcertID) REFERENCES Concert(ConcertID),
    CONSTRAINT FK_CheckinStaffAssignment_AssignedBy FOREIGN KEY (AssignedByUserID) REFERENCES UserAccount(UserID),
    CONSTRAINT CHK_StaffAssignment_Status CHECK (AssignmentStatus IN ('Active', 'Revoked'))
);
