-- Scoped administrative views; base-table DENY permissions remain in force.
GRANT SELECT ON dbo.VW_AdminConcerts TO api_service;
GRANT SELECT ON dbo.VW_AdminConcerts TO app_organizer;
GRANT SELECT ON dbo.VW_AdminCategories TO api_service;
GRANT SELECT ON dbo.VW_AdminCategories TO app_organizer;
GRANT SELECT ON dbo.VW_AdminPromotions TO api_service;
GRANT SELECT ON dbo.VW_AdminPromotions TO app_organizer;
GRANT SELECT ON dbo.VW_AdminDiscountCodes TO api_service;
GRANT SELECT ON dbo.VW_AdminDiscountCodes TO app_organizer;
GRANT SELECT ON dbo.VW_AdminRefunds TO api_service;
GRANT SELECT ON dbo.VW_AdminRefunds TO app_organizer;
GO

