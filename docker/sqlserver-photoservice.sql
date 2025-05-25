CREATE LOGIN PhotoService WITH PASSWORD = 'Passw0rd!', CHECK_POLICY = OFF;
CREATE DATABASE PhotoService;
ALTER AUTHORIZATION ON DATABASE::PhotoService TO PhotoService;
GO

USE PhotoService
GO

EXEC sys.sp_cdc_enable_db
GO
