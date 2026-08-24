INSERT INTO Role (RoleName, RoleStatus) 
VALUES 
('Admin', 'Active'),
('Organizer', 'Active'),
('Customer', 'Active'),
('Check-in Staff', 'Active');

INSERT INTO UserAccount (Username, AccountStatus, PasswordHash) 
VALUES ('system', 'Active', NULL);

INSERT INTO SystemConfiguration (ConfigurationKey, ConfigurationValue) 
VALUES 
('Default_Temporary_Hold_Duration', '900'),
('Waitlist_Opportunity_Duration', '3600'),
('Queue_Admission_Validity', '600');
