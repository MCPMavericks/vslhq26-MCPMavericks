/*
    JobsScript.sql - Demo SQL Agent jobs for JobGuardianAI, driven by a fault-injection
    control table instead of being hardcoded to one fixed outcome each.

    HOW TO DRIVE A DEMO
    --------------------
    Every job runs the same generic step. Each time it starts, it looks up its own row in
    dbo.JobOutcomeSettings to decide whether to succeed or fail with a specific canned
    error (see dbo.JobOutcomeCode for the full list of codes). To simulate a failure:

        UPDATE JobGuardianAI.dbo.JobOutcomeSettings
        SET OutcomeCode = 3, ModifiedDate = SYSUTCDATETIME()   -- 3 = Deadlock
        WHERE JobName = N'JG Demo - Deadlock Victim';

        EXEC msdb.dbo.sp_start_job @job_name = N'JG Demo - Deadlock Victim';

    To simulate "the underlying issue got fixed" (so the next run - manual, scheduled,
    or the agent's own retry - succeeds):

        UPDATE JobGuardianAI.dbo.JobOutcomeSettings
        SET OutcomeCode = 0, ModifiedDate = SYSUTCDATETIME()   -- 0 = Success
        WHERE JobName = N'JG Demo - Deadlock Victim';

    Every canned error message is written to contain the exact substring one of the
    dbo.KnowledgeBase.ErrorPattern entries matches, so every code produces a failure the
    agent can actually diagnose - see dbo.JobOutcomeCode for the full mapping.

    This script is safe to re-run: it drops and recreates the four demo jobs each time
    (so rehearsing a demo is just "run this script again"), but only seeds
    dbo.JobOutcomeSettings defaults for jobs that don't already have a row, so it won't
    clobber outcomes you've already set while testing.

    SCHEDULING
    ----------
    Each job also gets a "every 10 minutes" recurring schedule, created but DISABLED by
    default so nothing fires unexpectedly mid-demo. Enable it for a segment showing fully
    autonomous operation with:

        EXEC msdb.dbo.sp_update_schedule @name = N'Every 10 Minutes - <job name>', @enabled = 1;
*/

-------------------------------------------------------------------------------
-- 1. Fault-injection control tables (JobGuardianAI database)
-------------------------------------------------------------------------------
USE JobGuardianAI;
GO

IF OBJECT_ID(N'dbo.JobOutcomeSettings', N'U') IS NOT NULL DROP TABLE dbo.JobOutcomeSettings;
IF OBJECT_ID(N'dbo.JobOutcomeCode', N'U') IS NOT NULL DROP TABLE dbo.JobOutcomeCode;
GO

-- Lookup: maps a small integer code to a canned outcome. Error messages are written to
-- contain the exact substring a dbo.KnowledgeBase.ErrorPattern matches, so every code
-- reliably produces a diagnosable, KB-matchable failure during a demo.
CREATE TABLE dbo.JobOutcomeCode
(
    OutcomeCode     INT NOT NULL PRIMARY KEY,
    OutcomeName     NVARCHAR(100) NOT NULL,
    IsSuccess       BIT NOT NULL,
    ErrorMessage    NVARCHAR(1000) NULL,
    CONSTRAINT CK_JobOutcomeCode_ErrorMessage CHECK (IsSuccess = 1 OR ErrorMessage IS NOT NULL)
);
GO

INSERT INTO dbo.JobOutcomeCode (OutcomeCode, OutcomeName, IsSuccess, ErrorMessage)
VALUES
(0,  N'Success',              1, NULL),
(1,  N'DataValidation',       0, N'Conversion failed when converting the nvarchar value ''ABC'' to data type int in source row 42.'),
(2,  N'MissingFile',          0, N'Unable to locate the source extract. The system cannot find the file specified: \\fileserver\drop\extract.csv'),
(3,  N'Deadlock',             0, N'Transaction (Process ID 61) was deadlocked on lock resources with another process and has been chosen as the deadlock victim. Rerun the transaction.'),
(4,  N'LoginFailed',          0, N'Login failed for user ''svc_etl_reader''.'),
(5,  N'Timeout',              0, N'Query timeout expired. The wait operation timed out.'),
(6,  N'LoginTimeout',         0, N'Login timeout expired. Unable to connect to the target server within 30 seconds.'),
(7,  N'PermissionDenied',     0, N'The EXECUTE permission was denied on the object ''usp_LoadStaging''. Permission denied for principal ''job_svc_account''.'),
(8,  N'DiskFull',             0, N'Disk full: unable to write output file to D:\ExportData\output.csv.'),
(9,  N'DatabaseOffline',      0, N'Cannot open database "Reporting" requested by the login. The database is not accessible at this time.'),
(10, N'NetworkPathNotFound',  0, N'The network path was not found. Unable to reach \\fileserver\dropzone.'),
(11, N'DuplicateKey',         0, N'Violation of PRIMARY KEY constraint ''PK_Orders''. Cannot insert duplicate key in object ''dbo.Orders''.'),
(12, N'LogFull',              0, N'The transaction log for database ''Staging'' is full due to ''LOG_BACKUP''.'),
(13, N'BackupFailure',        0, N'Cannot open backup device ''\\backupshare\daily\staging.bak''. Operating system error 5(Access is denied.).'),
(14, N'DataOverflow',         0, N'Arithmetic overflow error converting IDENTITY to data type int.'),
(15, N'DataTruncation',       0, N'String or binary data would be truncated in table ''dbo.Customers'', column ''Email''.'),
(16, N'ReferentialIntegrity', 0, N'The INSERT statement conflicted with the FOREIGN KEY constraint ''FK_Orders_Customers''.'),
(17, N'StorageExhausted',     0, N'Could not allocate space for object ''dbo.StagingTable'' in database ''JobGuardianAI'' because the ''PRIMARY'' filegroup is full.');
GO

-- Per-job control switch: which outcome code should this job produce next time it runs.
CREATE TABLE dbo.JobOutcomeSettings
(
    JobName         NVARCHAR(200) NOT NULL PRIMARY KEY,
    OutcomeCode     INT NOT NULL
        CONSTRAINT FK_JobOutcomeSettings_OutcomeCode REFERENCES dbo.JobOutcomeCode (OutcomeCode),
    ModifiedDate    DATETIME2 NOT NULL
        CONSTRAINT DF_JobOutcomeSettings_ModifiedDate DEFAULT (SYSUTCDATETIME())
);
GO

INSERT INTO dbo.JobOutcomeSettings (JobName, OutcomeCode)
SELECT v.JobName, v.OutcomeCode
FROM (VALUES
    (N'JG Demo - Data Validation', 1),
    (N'JG Demo - Deadlock Victim', 3),
    (N'JG Demo - Missing File', 2),
    (N'JG Demo - Successful Job', 0)
) AS v(JobName, OutcomeCode)
WHERE NOT EXISTS (SELECT 1 FROM dbo.JobOutcomeSettings existing WHERE existing.JobName = v.JobName);
GO

-------------------------------------------------------------------------------
-- 2. SQL Agent jobs (msdb) - all four share the same outcome-driven step
-------------------------------------------------------------------------------
USE msdb;
GO

IF NOT EXISTS (SELECT name FROM msdb.dbo.syscategories WHERE name = N'[Uncategorized (Local)]' AND category_class = 1)
    EXEC msdb.dbo.sp_add_category @class = N'JOB', @type = N'LOCAL', @name = N'[Uncategorized (Local)]';
GO

-------------------------------------------------------------------------------
-- Job: JG Demo - Data Validation
-------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'JG Demo - Data Validation')
    EXEC msdb.dbo.sp_delete_job @job_name = N'JG Demo - Data Validation';
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT = 0
DECLARE @jobId BINARY(16)

EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'JG Demo - Data Validation',
        @enabled = 1,
        @notify_level_eventlog = 2,
        @delete_level = 0,
        @description = N'Demo job driven by JobGuardianAI.dbo.JobOutcomeSettings - defaults to a data validation failure.',
        @category_name = N'[Uncategorized (Local)]',
        @owner_login_name = N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Run Outcome',
        @step_id = 1,
        @cmdexec_success_code = 0,
        @on_success_action = 1,
        @on_fail_action = 2,
        @retry_attempts = 0,
        @retry_interval = 0,
        @subsystem = N'TSQL',
        @command = N'
DECLARE @JobName NVARCHAR(200) = N''JG Demo - Data Validation'';
DECLARE @Code INT, @IsSuccess BIT, @Msg NVARCHAR(1000);
SELECT @Code = s.OutcomeCode FROM JobGuardianAI.dbo.JobOutcomeSettings s WHERE s.JobName = @JobName;
SELECT @IsSuccess = c.IsSuccess, @Msg = c.ErrorMessage FROM JobGuardianAI.dbo.JobOutcomeCode c WHERE c.OutcomeCode = ISNULL(@Code, 0);
IF @IsSuccess = 1 OR @IsSuccess IS NULL
BEGIN
    PRINT N''Job completed successfully. (OutcomeCode='' + ISNULL(CAST(@Code AS NVARCHAR(10)), N''0 default'') + N'')'';
END
ELSE
BEGIN
    THROW 51000, @Msg, 1;
END',
        @database_name = N'master'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id = @jobId, @name = N'Every 10 Minutes - JG Demo - Data Validation',
        @enabled = 0,
        @freq_type = 4, @freq_interval = 1,
        @freq_subday_type = 4, @freq_subday_interval = 10,
        @active_start_time = 0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

-------------------------------------------------------------------------------
-- Job: JG Demo - Deadlock Victim
-------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'JG Demo - Deadlock Victim')
    EXEC msdb.dbo.sp_delete_job @job_name = N'JG Demo - Deadlock Victim';
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT = 0
DECLARE @jobId BINARY(16)

EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'JG Demo - Deadlock Victim',
        @enabled = 1,
        @notify_level_eventlog = 2,
        @delete_level = 0,
        @description = N'Demo job driven by JobGuardianAI.dbo.JobOutcomeSettings - defaults to a deadlock failure.',
        @category_name = N'[Uncategorized (Local)]',
        @owner_login_name = N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Run Outcome',
        @step_id = 1,
        @cmdexec_success_code = 0,
        @on_success_action = 1,
        @on_fail_action = 2,
        @retry_attempts = 0,
        @retry_interval = 0,
        @subsystem = N'TSQL',
        @command = N'
DECLARE @JobName NVARCHAR(200) = N''JG Demo - Deadlock Victim'';
DECLARE @Code INT, @IsSuccess BIT, @Msg NVARCHAR(1000);
SELECT @Code = s.OutcomeCode FROM JobGuardianAI.dbo.JobOutcomeSettings s WHERE s.JobName = @JobName;
SELECT @IsSuccess = c.IsSuccess, @Msg = c.ErrorMessage FROM JobGuardianAI.dbo.JobOutcomeCode c WHERE c.OutcomeCode = ISNULL(@Code, 0);
IF @IsSuccess = 1 OR @IsSuccess IS NULL
BEGIN
    PRINT N''Job completed successfully. (OutcomeCode='' + ISNULL(CAST(@Code AS NVARCHAR(10)), N''0 default'') + N'')'';
END
ELSE
BEGIN
    THROW 51000, @Msg, 1;
END',
        @database_name = N'master'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id = @jobId, @name = N'Every 10 Minutes - JG Demo - Deadlock Victim',
        @enabled = 0,
        @freq_type = 4, @freq_interval = 1,
        @freq_subday_type = 4, @freq_subday_interval = 10,
        @active_start_time = 0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

-------------------------------------------------------------------------------
-- Job: JG Demo - Missing File
-------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'JG Demo - Missing File')
    EXEC msdb.dbo.sp_delete_job @job_name = N'JG Demo - Missing File';
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT = 0
DECLARE @jobId BINARY(16)

EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'JG Demo - Missing File',
        @enabled = 1,
        @notify_level_eventlog = 2,
        @delete_level = 0,
        @description = N'Demo job driven by JobGuardianAI.dbo.JobOutcomeSettings - defaults to a missing file failure.',
        @category_name = N'[Uncategorized (Local)]',
        @owner_login_name = N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Run Outcome',
        @step_id = 1,
        @cmdexec_success_code = 0,
        @on_success_action = 1,
        @on_fail_action = 2,
        @retry_attempts = 0,
        @retry_interval = 0,
        @subsystem = N'TSQL',
        @command = N'
DECLARE @JobName NVARCHAR(200) = N''JG Demo - Missing File'';
DECLARE @Code INT, @IsSuccess BIT, @Msg NVARCHAR(1000);
SELECT @Code = s.OutcomeCode FROM JobGuardianAI.dbo.JobOutcomeSettings s WHERE s.JobName = @JobName;
SELECT @IsSuccess = c.IsSuccess, @Msg = c.ErrorMessage FROM JobGuardianAI.dbo.JobOutcomeCode c WHERE c.OutcomeCode = ISNULL(@Code, 0);
IF @IsSuccess = 1 OR @IsSuccess IS NULL
BEGIN
    PRINT N''Job completed successfully. (OutcomeCode='' + ISNULL(CAST(@Code AS NVARCHAR(10)), N''0 default'') + N'')'';
END
ELSE
BEGIN
    THROW 51000, @Msg, 1;
END',
        @database_name = N'master'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id = @jobId, @name = N'Every 10 Minutes - JG Demo - Missing File',
        @enabled = 0,
        @freq_type = 4, @freq_interval = 1,
        @freq_subday_type = 4, @freq_subday_interval = 10,
        @active_start_time = 0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO

-------------------------------------------------------------------------------
-- Job: JG Demo - Successful Job
-------------------------------------------------------------------------------
IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'JG Demo - Successful Job')
    EXEC msdb.dbo.sp_delete_job @job_name = N'JG Demo - Successful Job';
GO

BEGIN TRANSACTION
DECLARE @ReturnCode INT = 0
DECLARE @jobId BINARY(16)

EXEC @ReturnCode = msdb.dbo.sp_add_job @job_name = N'JG Demo - Successful Job',
        @enabled = 1,
        @notify_level_eventlog = 2,
        @delete_level = 0,
        @description = N'Demo job driven by JobGuardianAI.dbo.JobOutcomeSettings - defaults to success.',
        @category_name = N'[Uncategorized (Local)]',
        @owner_login_name = N'sa', @job_id = @jobId OUTPUT
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobstep @job_id = @jobId, @step_name = N'Run Outcome',
        @step_id = 1,
        @cmdexec_success_code = 0,
        @on_success_action = 1,
        @on_fail_action = 2,
        @retry_attempts = 0,
        @retry_interval = 0,
        @subsystem = N'TSQL',
        @command = N'
DECLARE @JobName NVARCHAR(200) = N''JG Demo - Successful Job'';
DECLARE @Code INT, @IsSuccess BIT, @Msg NVARCHAR(1000);
SELECT @Code = s.OutcomeCode FROM JobGuardianAI.dbo.JobOutcomeSettings s WHERE s.JobName = @JobName;
SELECT @IsSuccess = c.IsSuccess, @Msg = c.ErrorMessage FROM JobGuardianAI.dbo.JobOutcomeCode c WHERE c.OutcomeCode = ISNULL(@Code, 0);
IF @IsSuccess = 1 OR @IsSuccess IS NULL
BEGIN
    PRINT N''Job completed successfully. (OutcomeCode='' + ISNULL(CAST(@Code AS NVARCHAR(10)), N''0 default'') + N'')'';
END
ELSE
BEGIN
    THROW 51000, @Msg, 1;
END',
        @database_name = N'master'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_update_job @job_id = @jobId, @start_step_id = 1
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobschedule @job_id = @jobId, @name = N'Every 10 Minutes - JG Demo - Successful Job',
        @enabled = 0,
        @freq_type = 4, @freq_interval = 1,
        @freq_subday_type = 4, @freq_subday_interval = 10,
        @active_start_time = 0
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback

EXEC @ReturnCode = msdb.dbo.sp_add_jobserver @job_id = @jobId, @server_name = N'(local)'
IF (@@ERROR <> 0 OR @ReturnCode <> 0) GOTO QuitWithRollback
COMMIT TRANSACTION
GOTO EndSave
QuitWithRollback:
    IF (@@TRANCOUNT > 0) ROLLBACK TRANSACTION
EndSave:
GO
