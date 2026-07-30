USE msdb;
GO

DECLARE @JobId uniqueidentifier;

SELECT @JobId=job_id FROM dbo.sysjobs WHERE name=N'JG Demo - Successful Job';
IF @JobId IS NULL
BEGIN
 EXEC dbo.sp_add_job @job_name=N'JG Demo - Successful Job',@enabled=0,@description=N'Demo job that succeeds.',@owner_login_name=N'sa',@job_id=@JobId OUTPUT;
 EXEC dbo.sp_add_jobstep @job_id=@JobId,@step_name=N'Insert sample row',@subsystem=N'TSQL',@database_name=N'JobGuardianAI',
      @command=N'INSERT dbo.SampleData(SampleText) VALUES(N''Successful demo execution''); WAITFOR DELAY ''00:00:02'';';
 EXEC dbo.sp_add_jobserver @job_id=@JobId;
END;
GO

DECLARE @JobId uniqueidentifier;
SELECT @JobId=job_id FROM dbo.sysjobs WHERE name=N'JG Demo - Missing File';
IF @JobId IS NULL
BEGIN
 EXEC dbo.sp_add_job @job_name=N'JG Demo - Missing File',@enabled=0,@description=N'Demo failure: missing file.',@owner_login_name=N'sa',@job_id=@JobId OUTPUT;
 EXEC dbo.sp_add_jobstep @job_id=@JobId,@step_name=N'Import expected file',@subsystem=N'TSQL',@database_name=N'JobGuardianAI',
      @command=N'THROW 51001, ''Cannot find the file \\DemoFileServer\Daily\LoanImport_20260728.csv. The system cannot find the file specified.'', 1;';
 EXEC dbo.sp_add_jobserver @job_id=@JobId;
END;
GO

DECLARE @JobId uniqueidentifier;
SELECT @JobId=job_id FROM dbo.sysjobs WHERE name=N'JG Demo - Deadlock Victim';
IF @JobId IS NULL
BEGIN
 EXEC dbo.sp_add_job @job_name=N'JG Demo - Deadlock Victim',@enabled=0,@description=N'Demo failure: deadlock message.',@owner_login_name=N'sa',@job_id=@JobId OUTPUT;
 EXEC dbo.sp_add_jobstep @job_id=@JobId,@step_name=N'Update business data',@subsystem=N'TSQL',@database_name=N'JobGuardianAI',
      @command=N'THROW 51002, ''Transaction was deadlocked on lock resources with another process and has been chosen as the deadlock victim. Error: 1205.'', 1;';
 EXEC dbo.sp_add_jobserver @job_id=@JobId;
END;
GO

DECLARE @JobId uniqueidentifier;
SELECT @JobId=job_id FROM dbo.sysjobs WHERE name=N'JG Demo - Data Validation';
IF @JobId IS NULL
BEGIN
 EXEC dbo.sp_add_job @job_name=N'JG Demo - Data Validation',@enabled=0,@description=N'Demo failure: invalid source data.',@owner_login_name=N'sa',@job_id=@JobId OUTPUT;
 EXEC dbo.sp_add_jobstep @job_id=@JobId,@step_name=N'Validate source data',@subsystem=N'TSQL',@database_name=N'JobGuardianAI',
      @command=N'THROW 51003, ''Conversion failed when converting the nvarchar value ABC to data type int in source row 42.'', 1;';
 EXEC dbo.sp_add_jobserver @job_id=@JobId;
END;
GO
