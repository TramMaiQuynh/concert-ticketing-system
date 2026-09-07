-- ============================================================
-- SeedData.sql - Du lieu nen bat buoc (bootstrap, §23.7)
-- Phai ton tai truoc khi bat ky nghiep vu nao van hanh.
-- ============================================================

INSERT INTO Role (RoleName, RoleStatus) 
VALUES 
('Admin', 'Active'),
('Organizer', 'Active'),
('Customer', 'Active'),
('Check-in Staff', 'Active');

-- Tai khoan du tru cho cac tien trinh tu dong SIP1-SIP3/SIP5.
-- Khong duoc gan Role, khong the dang nhap (PasswordHash = NULL).
INSERT INTO UserAccount (Username, AccountStatus, PasswordHash) 
VALUES ('system', 'Active', NULL);

INSERT INTO SystemConfiguration (ConfigurationKey, ConfigurationValue) 
VALUES 
('Default_Temporary_Hold_Duration', '900'),   -- BR53: thoi gian giu cho mac dinh (giay)
('Waitlist_Opportunity_Duration',   '900'),   -- BR44: han su dung co hoi Waitlist = 15 phut (giay).
-- 900 chu khong phai 3600. BR44, §12.18 va §10.1 deu ghi 15 phut; don vi la giay,
-- xac nhan boi sp_AllocateWaitlist dung DATEADD(SECOND, @OpportunityDuration, @Now)
-- - cung khuon voi Default_Temporary_Hold_Duration = 900 vốn tao ra dong ho 15:00.
-- Gia tri 3600 truoc day = 60 phut, gap BON lan quy dinh: ghe OnHoldForWaitlist bi
-- giam ngoai vong ban gap bon thoi gian cho phep, dung vao luc can quay vong nhat.
-- Khong co cot ghi de per-Concert cho khoa nay, nen day la nguon duy nhat.
('Queue_Admission_Validity',        '600'),   -- D4/BR47b: booking_ttl mac dinh (giay)
-- BR47: suc chua admission mac dinh khi Queue duoc tao ngam boi nguoi vao hang
-- dau tien. Truoc day sp_JoinQueue doc dung khoa nay nhung khoa KHONG duoc seed,
-- nen no luon roi ve mot hang so 1000 nam trong ma - dung kieu "cau hinh gia"
-- ma chinh comment cua SP tuyen bo la khong hardcode.
('Queue_Default_Admission_Capacity','1000');
