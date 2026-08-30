-- ============================================================
-- HangfireSchema.sql
-- Tao schema [HangFire] va cac bang mac dinh cho Hangfire.
-- Chay bang quyen sysadmin/db_owner trong deploy script 
-- thay vi de Hangfire tu tao luc runtime (bao mat hon).
-- ============================================================

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'HangFire')
BEGIN
    EXEC('CREATE SCHEMA [HangFire]');
END
GO

-- 1. Schema
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[Schema]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[Schema](
    [Version] [int] NOT NULL,
    CONSTRAINT [PK_HangFire_Schema] PRIMARY KEY CLUSTERED ([Version] ASC)
)
END
GO
IF NOT EXISTS (SELECT 1 FROM [HangFire].[Schema])
BEGIN
    INSERT INTO [HangFire].[Schema] ([Version]) VALUES (7)
END
GO

-- 2. Job
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[Job]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[Job](
    [Id] [int] IDENTITY(1,1) NOT NULL,
    [StateId] [int] NULL,
    [StateName] [nvarchar](20) NULL,
    [InvocationData] [nvarchar](max) NOT NULL,
    [Arguments] [nvarchar](max) NOT NULL,
    [CreatedAt] [datetime] NOT NULL,
    [ExpireAt] [datetime] NULL,
    CONSTRAINT [PK_HangFire_Job] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 3. State
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[State]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[State](
    [Id] [int] IDENTITY(1,1) NOT NULL,
    [JobId] [int] NOT NULL,
    [Name] [nvarchar](20) NOT NULL,
    [Reason] [nvarchar](100) NULL,
    [CreatedAt] [datetime] NOT NULL,
    [Data] [nvarchar](max) NULL,
    CONSTRAINT [PK_HangFire_State] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 4. JobParameter
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[JobParameter]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[JobParameter](
    [JobId] [int] NOT NULL,
    [Name] [nvarchar](40) NOT NULL,
    [Value] [nvarchar](max) NULL,
    CONSTRAINT [PK_HangFire_JobParameter] PRIMARY KEY CLUSTERED ([JobId] ASC, [Name] ASC)
)
END
GO

-- 5. JobQueue
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[JobQueue]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[JobQueue](
    [Id] [int] IDENTITY(1,1) NOT NULL,
    [JobId] [int] NOT NULL,
    [Queue] [nvarchar](50) NOT NULL,
    [FetchedAt] [datetime] NULL,
    CONSTRAINT [PK_HangFire_JobQueue] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 6. Server
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[Server]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[Server](
    [Id] [nvarchar](200) NOT NULL,
    [Data] [nvarchar](max) NULL,
    [LastHeartbeat] [datetime] NOT NULL,
    CONSTRAINT [PK_HangFire_Server] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 7. List
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[List]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[List](
    [Id] [int] IDENTITY(1,1) NOT NULL,
    [Key] [nvarchar](100) NOT NULL,
    [Value] [nvarchar](max) NULL,
    [ExpireAt] [datetime] NULL,
    CONSTRAINT [PK_HangFire_List] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 8. Set
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[Set]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[Set](
    [Id] [int] IDENTITY(1,1) NOT NULL,
    [Key] [nvarchar](100) NOT NULL,
    [Score] [float] NOT NULL,
    [Value] [nvarchar](256) NOT NULL,
    [ExpireAt] [datetime] NULL,
    CONSTRAINT [PK_HangFire_Set] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 9. Counter
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[Counter]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[Counter](
    [Id] [int] IDENTITY(1,1) NOT NULL,
    [Key] [nvarchar](100) NOT NULL,
    [Value] [int] NOT NULL,
    [ExpireAt] [datetime] NULL,
    CONSTRAINT [PK_HangFire_Counter] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 10. Hash
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[Hash]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[Hash](
    [Id] [int] IDENTITY(1,1) NOT NULL,
    [Key] [nvarchar](100) NOT NULL,
    [Field] [nvarchar](100) NOT NULL,
    [Value] [nvarchar](max) NULL,
    [ExpireAt] [datetime] NULL,
    CONSTRAINT [PK_HangFire_Hash] PRIMARY KEY CLUSTERED ([Id] ASC)
)
END
GO

-- 11. AggregatedCounter
IF NOT EXISTS (SELECT 1 FROM sys.objects WHERE object_id = OBJECT_ID(N'[HangFire].[AggregatedCounter]') AND type in (N'U'))
BEGIN
CREATE TABLE [HangFire].[AggregatedCounter](
    [Key] [nvarchar](100) NOT NULL,
    [Value] [bigint] NOT NULL,
    [ExpireAt] [datetime] NULL,
    CONSTRAINT [PK_HangFire_AggregatedCounter] PRIMARY KEY CLUSTERED ([Key] ASC)
)
END
GO

-- FK & INDEXES
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[HangFire].[FK_HangFire_JobParameter_Job]') AND parent_object_id = OBJECT_ID(N'[HangFire].[JobParameter]'))
ALTER TABLE [HangFire].[JobParameter] ADD CONSTRAINT [FK_HangFire_JobParameter_Job] FOREIGN KEY([JobId])
REFERENCES [HangFire].[Job] ([Id]) ON UPDATE CASCADE ON DELETE CASCADE
GO

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE object_id = OBJECT_ID(N'[HangFire].[FK_HangFire_State_Job]') AND parent_object_id = OBJECT_ID(N'[HangFire].[State]'))
ALTER TABLE [HangFire].[State] ADD CONSTRAINT [FK_HangFire_State_Job] FOREIGN KEY([JobId])
REFERENCES [HangFire].[Job] ([Id]) ON UPDATE CASCADE ON DELETE CASCADE
GO

-- Non-clustered Indexes for better performance
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[HangFire].[Job]') AND name = N'IX_HangFire_Job_StateName')
CREATE NONCLUSTERED INDEX [IX_HangFire_Job_StateName] ON [HangFire].[Job] ([StateName] ASC) WHERE [StateName] IS NOT NULL
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'[HangFire].[JobQueue]') AND name = N'IX_HangFire_JobQueue_QueueAndFetchedAt')
CREATE NONCLUSTERED INDEX [IX_HangFire_JobQueue_QueueAndFetchedAt] ON [HangFire].[JobQueue] ([Queue] ASC, [FetchedAt] ASC)
GO
