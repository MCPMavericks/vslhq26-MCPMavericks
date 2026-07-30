-- ============================================================
-- CreateSimulatedJobs.sql
--
-- Creates three SQL Server Agent jobs that
-- simulate realistic failure scenarios from the KnowledgeBase.
--
-- Outcome distribution per execution (ABS(CHECKSUM(NEWID())) % 10):
--   Roll 0-1  (20%) -> Success
--   Roll 2    (10%) -> Missing File   : "cannot find the file"
--   Roll 3    (10%) -> Deadlock       : "deadlock victim"
--   Roll 4    (10%) -> Login Failure  : "login failed"
--   Roll 5    (10%) -> Timeout        : "timeout"
--   Roll 6    (10%) -> Permission     : "permission denied"
--   Roll 7    (10%) -> Disk Full      : "disk full"
--   Roll 8    (10%) -> DB Offline     : "database is not accessible"
--   Roll 9    (10%) -> Network        : "network path not found"
--
-- Schedule: every 5 minutes, so history accumulates quickly.
-- Requires SQL Server Agent (not available on LocalDB).
-- ============================================================

USE msdb;
GO

-- ----------------------------------------------------------
-- Shared step body (parametrised by job name at paste-time)
-- ----------------------------------------------------------
-- Each job gets its own copy of this logic so failures are
-- independent of one another across concurrent runs.
-- ----------------------------------------------------------

-- ---- Clean up any pre-existing jobs ----------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Daily Loan Import')
	EXEC msdb.dbo.sp_delete_job @job_name = N'Daily Loan Import', @delete_unused_schedule = 1;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Nightly Payroll Export')
	EXEC msdb.dbo.sp_delete_job @job_name = N'Nightly Payroll Export', @delete_unused_schedule = 1;

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'Hourly Reporting Refresh')
	EXEC msdb.dbo.sp_delete_job @job_name = N'Hourly Reporting Refresh', @delete_unused_schedule = 1;
GO

-- ============================================================
-- JOB 1 — Daily Loan Import simulation
-- ============================================================
DECLARE @job1_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
	@job_name        = N'Daily Loan Import',
	@description     = N'Simulates daily loan file import with random failure states from the KnowledgeBase.',
	@enabled         = 1,
	@notify_level_eventlog = 2,   -- log on failure
	@job_id          = @job1_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
	@job_id          = @job1_id,
	@step_name       = N'Run Import',
	@subsystem       = N'TSQL',
	@database_name   = N'JobGuardianAI',
	@on_success_action = 1,  -- quit with success
	@on_fail_action    = 2,  -- quit with failure
	@command         = N'
DECLARE @roll INT = ABS(CHECKSUM(NEWID())) % 10;

IF @roll <= 1
BEGIN
	PRINT N''Daily Loan Import completed successfully.'';
END
ELSE IF @roll = 2
	RAISERROR(N''cannot find the file: D:\LoanData\daily_import.csv'', 16, 1);
ELSE IF @roll = 3
	RAISERROR(N''deadlock victim detected while inserting into dbo.LoanStaging'', 16, 1);
ELSE IF @roll = 4
	RAISERROR(N''login failed for user ''''ETLServiceAccount'''''' , 16, 1);
ELSE IF @roll = 5
	RAISERROR(N''timeout expired during bulk insert after 300 seconds'', 16, 1);
ELSE IF @roll = 6
	RAISERROR(N''permission denied on object ''''dbo.LoanStaging'''''' , 16, 1);
ELSE IF @roll = 7
	RAISERROR(N''disk full on drive D:\LoanData'', 16, 1);
ELSE IF @roll = 8
	RAISERROR(N''database is not accessible: LoanArchive'', 16, 1);
ELSE
	RAISERROR(N''network path not found: \\fileserver\loanshare\daily'', 16, 1);
';

EXEC msdb.dbo.sp_add_schedule
	@schedule_name      = N'job1_every5min',
	@freq_type          = 4,      -- daily
	@freq_interval      = 1,
	@freq_subday_type   = 4,      -- minutes
	@freq_subday_interval = 5;

EXEC msdb.dbo.sp_attach_schedule
	@job_id       = @job1_id,
	@schedule_name = N'job1_every5min';

EXEC msdb.dbo.sp_add_jobserver
	@job_id   = @job1_id,
	@server_name = N'(local)';

PRINT N'Daily Loan Import created: ' + CAST(@job1_id AS NVARCHAR(50));
GO

-- ============================================================
-- JOB 2 — Nightly Payroll Export simulation
-- ============================================================
DECLARE @job2_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
	@job_name        = N'Nightly Payroll Export',
	@description     = N'Simulates nightly payroll export with random failure states from the KnowledgeBase.',
	@enabled         = 1,
	@notify_level_eventlog = 2,
	@job_id          = @job2_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
	@job_id          = @job2_id,
	@step_name       = N'Run Export',
	@subsystem       = N'TSQL',
	@database_name   = N'JobGuardianAI',
	@on_success_action = 1,
	@on_fail_action    = 2,
	@command         = N'
DECLARE @roll INT = ABS(CHECKSUM(NEWID())) % 10;

IF @roll <= 1
BEGIN
	PRINT N''Nightly Payroll Export completed successfully.'';
END
ELSE IF @roll = 2
	RAISERROR(N''cannot find the file: E:\Payroll\payroll_config.xml'', 16, 1);
ELSE IF @roll = 3
	RAISERROR(N''deadlock victim detected while updating dbo.PayrollSummary'', 16, 1);
ELSE IF @roll = 4
	RAISERROR(N''login failed for user ''''PayrollSvcUser'''''' , 16, 1);
ELSE IF @roll = 5
	RAISERROR(N''timeout expired during payroll aggregation after 600 seconds'', 16, 1);
ELSE IF @roll = 6
	RAISERROR(N''permission denied on object ''''dbo.PayrollExport'''''' , 16, 1);
ELSE IF @roll = 7
	RAISERROR(N''disk full on drive E:\PayrollArchive'', 16, 1);
ELSE IF @roll = 8
	RAISERROR(N''database is not accessible: PayrollHistory'', 16, 1);
ELSE
	RAISERROR(N''network path not found: \\hrserver\payroll\nightly'', 16, 1);
';

EXEC msdb.dbo.sp_add_schedule
	@schedule_name      = N'job2_every5min',
	@freq_type          = 4,
	@freq_interval      = 1,
	@freq_subday_type   = 4,
	@freq_subday_interval = 5;

EXEC msdb.dbo.sp_attach_schedule
	@job_id        = @job2_id,
	@schedule_name = N'job2_every5min';

EXEC msdb.dbo.sp_add_jobserver
	@job_id      = @job2_id,
	@server_name = N'(local)';

PRINT N'Nightly Payroll Export created: ' + CAST(@job2_id AS NVARCHAR(50));
GO

-- ============================================================
-- JOB 3 — Hourly Reporting Refresh simulation
-- ============================================================
DECLARE @job3_id UNIQUEIDENTIFIER;

EXEC msdb.dbo.sp_add_job
	@job_name        = N'Hourly Reporting Refresh',
	@description     = N'Simulates hourly reporting refresh with random failure states from the KnowledgeBase.',
	@enabled         = 1,
	@notify_level_eventlog = 2,
	@job_id          = @job3_id OUTPUT;

EXEC msdb.dbo.sp_add_jobstep
	@job_id          = @job3_id,
	@step_name       = N'Refresh Reports',
	@subsystem       = N'TSQL',
	@database_name   = N'JobGuardianAI',
	@on_success_action = 1,
	@on_fail_action    = 2,
	@command         = N'
DECLARE @roll INT = ABS(CHECKSUM(NEWID())) % 10;

IF @roll <= 1
BEGIN
	PRINT N''Hourly Reporting Refresh completed successfully.'';
END
ELSE IF @roll = 2
	RAISERROR(N''cannot find the file: C:\Reports\template_base.rdl'', 16, 1);
ELSE IF @roll = 3
	RAISERROR(N''deadlock victim detected while refreshing dbo.ReportCache'', 16, 1);
ELSE IF @roll = 4
	RAISERROR(N''login failed for user ''''ReportingSvcAccount'''''' , 16, 1);
ELSE IF @roll = 5
	RAISERROR(N''timeout expired during report dataset refresh after 120 seconds'', 16, 1);
ELSE IF @roll = 6
	RAISERROR(N''permission denied on object ''''dbo.SalesSummaryView'''''' , 16, 1);
ELSE IF @roll = 7
	RAISERROR(N''disk full on drive C:\ReportOutput'', 16, 1);
ELSE IF @roll = 8
	RAISERROR(N''database is not accessible: ReportingWarehouse'', 16, 1);
ELSE
	RAISERROR(N''network path not found: \\reportserver\outputs\hourly'', 16, 1);
';

EXEC msdb.dbo.sp_add_schedule
	@schedule_name      = N'job3_every5min',
	@freq_type          = 4,
	@freq_interval      = 1,
	@freq_subday_type   = 4,
	@freq_subday_interval = 5;

EXEC msdb.dbo.sp_attach_schedule
	@job_id        = @job3_id,
	@schedule_name = N'job3_every5min';

EXEC msdb.dbo.sp_add_jobserver
	@job_id      = @job3_id,
	@server_name = N'(local)';

PRINT N'Hourly Reporting Refresh created: ' + CAST(@job3_id AS NVARCHAR(50));
GO
