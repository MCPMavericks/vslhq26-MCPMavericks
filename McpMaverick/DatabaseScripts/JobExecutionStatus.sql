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
        h.instance_id,
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
),
-- The step_id = 0 "(Job outcome)" row above only ever contains a generic summary
-- like "the last step to run was step 1" - the REAL error text is logged in a
-- separate step-level row. SQL Agent logs that row immediately before the job-outcome
-- row for the same execution, so instance_id = (job outcome's instance_id - 1)
-- reliably identifies the matching step for single-step jobs.
LatestStepDetail
AS
(
    SELECT
        h.job_id,
        h.instance_id,
        h.message,
        ROW_NUMBER() OVER
        (
            PARTITION BY h.job_id
            ORDER BY h.instance_id DESC
        ) AS rn
    FROM msdb.dbo.sysjobhistory h
    WHERE h.step_id <> 0
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

    -- SQL Agent history is always recorded in the server's local time, but
    -- ActionHistory.ExecutedDate is stored via SYSUTCDATETIME(). Expose a UTC
    -- version here too so the two can be compared on the same clock.
    DATEADD
    (
        SECOND,
        DATEDIFF(SECOND, GETDATE(), GETUTCDATE()),
        msdb.dbo.agent_datetime(le.run_date, le.run_time)
    )                            AS LastExecutionTimeUtc,

    (
        (le.run_duration / 10000) * 3600 +
        ((le.run_duration % 10000) / 100) * 60 +
        (le.run_duration % 100)
    )                            AS DurationSeconds,

    COALESCE(sd.message, le.message) AS ErrorMessage,

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
      AND le.rn = 1

LEFT JOIN LatestStepDetail sd
       ON j.job_id = sd.job_id
      AND sd.rn = 1;
GO

CREATE TABLE dbo.KnowledgeBase
(
    KnowledgeBaseId     INT IDENTITY(1,1) PRIMARY KEY,
    FailureType         NVARCHAR(100) NOT NULL,
    ErrorPattern        NVARCHAR(500) NOT NULL,
    RootCause           NVARCHAR(1000) NOT NULL,
    RecommendedAction   NVARCHAR(1000) NOT NULL,
    McpTool             NVARCHAR(100) NOT NULL,
    AutomationLevel     NVARCHAR(20) NOT NULL
        CONSTRAINT CK_KnowledgeBase_AutomationLevel
        CHECK (AutomationLevel IN ('Automatic', 'Approval', 'Manual')),
    Confidence          DECIMAL(5,2) NOT NULL,
    IsActive            BIT NOT NULL
        CONSTRAINT DF_KnowledgeBase_IsActive
        DEFAULT (1),

    CreatedDate         DATETIME2 NOT NULL
        CONSTRAINT DF_KnowledgeBase_CreatedDate
        DEFAULT (SYSUTCDATETIME())
);
GO

-- AutomationLevel/McpTool are kept consistent with what the agent will actually do:
--   Automatic -> RetryJobAsync is called directly, no human involved.
--   Approval  -> a human should verify/decide before any retry happens (SendEmail today).
--   Manual    -> the cause requires human investigation or infrastructure action (SendEmail).
-- Where ErrorPattern values could both match the same message (e.g. "timeout" is a
-- substring of "login timeout expired"), the more specific pattern is given a higher
-- Confidence so it wins the tie-break.
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
'Notify the file owner to confirm the file has landed; only retry once confirmed, since retrying blindly will not fix a missing file.',
'SendEmail',
'Approval',
98
),

(
'Deadlock',
'deadlock victim',
'SQL Server selected this process as the deadlock victim.',
'Retry the SQL Agent job.',
'RetryJobAsync',
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
'RetryJobAsync',
'Automatic',
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
'Verify network connectivity, then retry.',
'SendEmail',
'Approval',
93
),

(
'Duplicate Key',
'violation of primary key constraint',
'The job attempted to insert a row that violates a unique/primary key constraint, usually from reprocessing the same batch twice.',
'Check whether the job ran twice or source data contains duplicates; cleanse before reloading.',
'SendEmail',
'Manual',
94
),

(
'Duplicate Key',
'cannot insert duplicate key',
'The job attempted to insert a row that already exists, usually from reprocessing the same batch twice.',
'Check whether the job ran twice or source data contains duplicates; cleanse before reloading.',
'SendEmail',
'Manual',
94
),

(
'Log Full',
'the transaction log for database',
'The transaction log ran out of space, likely from a long-running transaction or missing log backups.',
'Free log space (backup the log or grow the file) before retrying job execution.',
'SendEmail',
'Manual',
97
),

(
'Backup Failure',
'cannot open backup device',
'The backup destination path or device could not be opened - the share may be down or out of space.',
'Verify the backup destination is reachable and has free space, then retry.',
'SendEmail',
'Approval',
95
),

(
'Data Overflow',
'arithmetic overflow',
'Incoming data exceeded the target column''s numeric range.',
'Review source data for out-of-range values before reloading.',
'SendEmail',
'Manual',
90
),

(
'Data Truncation',
'string or binary data would be truncated',
'Incoming data was longer than the target column allows.',
'Review source data for oversized values before reloading.',
'SendEmail',
'Manual',
90
),

(
'Referential Integrity',
'conflicted with the foreign key constraint',
'The job tried to insert/update a row referencing a parent record that does not exist yet, often from out-of-order ETL steps.',
'Check upstream job/table load order; reload parent tables first.',
'SendEmail',
'Manual',
92
),

(
'Connection Timeout',
'login timeout expired',
'The job could not establish a database connection within the timeout window, usually from transient server load.',
'Retry the job; if it recurs, check server load and connection pool exhaustion.',
'RetryJobAsync',
'Automatic',
95
),

(
'Storage Exhausted',
'could not allocate space',
'The database or tempdb ran out of allocated space.',
'Free or grow storage before retrying job execution.',
'SendEmail',
'Manual',
96
),

(
'Data Validation',
'conversion failed',
'Source data contained a value that could not be converted to the target column''s data type.',
'Review the source row identified in the error for bad/malformed data before reloading.',
'SendEmail',
'Manual',
91
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
        DEFAULT (SYSUTCDATETIME()),
    -- Exact JobStatus.LastExecutionTimeUtc of the run this action was taken for.
    -- Lets the agent match "have I already handled THIS run?" by equality instead
    -- of inferring it from relative timestamp ordering.
    JobLastExecutionTimeUtc DATETIME2 NULL
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