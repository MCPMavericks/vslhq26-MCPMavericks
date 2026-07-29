USE master;
GO

IF DB_ID(N'JobGuardianAI') IS NULL
BEGIN
    PRINT N'Creating database JobGuardianAI...';
    CREATE DATABASE JobGuardianAI;
END
ELSE
BEGIN
    PRINT N'Database JobGuardianAI already exists.';
END;
GO

USE JobGuardianAI;
GO

CREATE OR ALTER VIEW dbo.JobStatus
AS
WITH LatestExecution
AS
(
    SELECT
        h.job_id,
        h.run_status,
        h.run_date,
        h.run_time,
        h.run_duration,
        h.message,
        h.step_id,
        ROW_NUMBER() OVER
        (
            PARTITION BY h.job_id
            ORDER BY h.instance_id DESC
        ) AS rn
    FROM msdb.dbo.sysjobhistory h
    WHERE h.step_id = 0
)
SELECT

    j.job_id                     AS JobId,

    j.name                       AS JobName,

    CASE le.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'Running'
        ELSE 'Unknown'
    END                          AS CurrentStatus,

    msdb.dbo.agent_datetime
    (
        le.run_date,
        le.run_time
    )                            AS LastExecutionTime,

    (
        (le.run_duration / 10000) * 3600 +
        ((le.run_duration % 10000) / 100) * 60 +
        (le.run_duration % 100)
    )                            AS DurationSeconds,

    le.message                   AS ErrorMessage,

    CASE
        WHEN le.run_status = 0 THEN 1
        ELSE 0
    END                          AS IsFailed,

    CASE
        WHEN j.enabled = 1 THEN 1
        ELSE 0
    END                          AS IsEnabled,

    @@SERVERNAME                 AS ServerName

FROM msdb.dbo.sysjobs j

LEFT JOIN LatestExecution le
       ON j.job_id = le.job_id
      AND le.rn = 1;
GO

CREATE TABLE dbo.KnowledgeBase
(
    KnowledgeBaseId     INT IDENTITY(1,1) PRIMARY KEY,
    FailureType         NVARCHAR(100) NOT NULL,
    ErrorPattern        NVARCHAR(500) NOT NULL,
    RootCause           NVARCHAR(1000) NOT NULL,
    RecommendedAction   NVARCHAR(1000) NOT NULL,
    McpTool             NVARCHAR(100) NOT NULL,
    AutomationLevel     NVARCHAR(20) NOT NULL,
    Confidence          DECIMAL(5,2) NOT NULL,
    IsActive            BIT NOT NULL
        CONSTRAINT DF_KnowledgeBase_IsActive
        DEFAULT (1),

    CreatedDate         DATETIME2 NOT NULL
        CONSTRAINT DF_KnowledgeBase_CreatedDate
        DEFAULT (SYSUTCDATETIME())
);
GO

INSERT INTO dbo.KnowledgeBase
(
    FailureType,
    ErrorPattern,
    RootCause,
    RecommendedAction,
    McpTool,
    AutomationLevel,
    Confidence
)
VALUES

(
'Missing File',
'cannot find the file',
'The expected input file was not found.',
'Notify file owner and retry the SQL Agent job.',
'RetryJob',
'Automatic',
98
),

(
'Deadlock',
'deadlock victim',
'SQL Server selected this process as the deadlock victim.',
'Retry the SQL Agent job.',
'RetryJob',
'Automatic',
96
),

(
'Login Failure',
'login failed',
'Database authentication failed.',
'Notify DBA team.',
'SendEmail',
'Manual',
99
),

(
'Timeout',
'timeout',
'Execution exceeded the configured timeout.',
'Retry after five minutes.',
'RetryJob',
'Approval',
92
),

(
'Permission',
'permission denied',
'Application account lacks required permissions.',
'Notify application owner.',
'SendEmail',
'Manual',
95
),

(
'Disk Full',
'disk full',
'Destination drive is full.',
'Notify Infrastructure team.',
'SendEmail',
'Manual',
97
),

(
'Database Offline',
'database is not accessible',
'Target database is offline.',
'Notify DBA immediately.',
'SendEmail',
'Manual',
99
),

(
'Network',
'network path not found',
'Network share is unavailable.',
'Verify network connectivity and retry.',
'RetryJob',
'Approval',
93
);
GO

CREATE TABLE dbo.ActionHistory
(
    ActionHistoryId     INT IDENTITY(1,1) PRIMARY KEY,
    JobName             NVARCHAR(200) NOT NULL,
    ErrorMessage        NVARCHAR(MAX) NULL,
    RootCause           NVARCHAR(1000) NULL,
    ActionName          NVARCHAR(100) NOT NULL,
    ActionResult        NVARCHAR(50) NOT NULL,
    McpTool             NVARCHAR(100) NULL,
    ExecutedBy          NVARCHAR(100) NULL,
    ExecutedDate        DATETIME2 NOT NULL
        CONSTRAINT DF_ActionHistory_ExecutedDate
        DEFAULT (SYSUTCDATETIME())
);
GO

INSERT INTO dbo.ActionHistory
(
    JobName,
    ErrorMessage,
    RootCause,
    ActionName,
    ActionResult,
    McpTool,
    ExecutedBy
)
VALUES
(
'Daily Loan Import',
'Cannot find the file.',
'Input file missing.',
'Retry Job',
'Success',
'RetryJob',
'JobGuardian AI'
);
GO