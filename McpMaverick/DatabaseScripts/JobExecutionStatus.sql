USE master;
GO

IF DB_ID(N'JobGuardianAI') IS NULL
BEGIN
    PRINT 'Creating database JobGuardianAI...';

    CREATE DATABASE JobGuardianAI;

    PRINT 'JobGuardianAI database created successfully.';
END
ELSE
BEGIN
    PRINT 'JobGuardianAI database already exists.';
END
GO


Use JobGuardianAI
GO

CREATE OR ALTER VIEW dbo.JobExecutionStatus
AS
WITH LatestJobHistory
AS
(
    SELECT
        h.job_id,
        h.run_status,
        h.run_date,
        h.run_time,
        h.run_duration,
        h.message,
        h.instance_id,
        ROW_NUMBER() OVER
        (
            PARTITION BY h.job_id
            ORDER BY h.instance_id DESC
        ) AS rn
    FROM msdb.dbo.sysjobhistory h
    WHERE h.step_id = 0
)
SELECT
    j.job_id AS JobId,
    j.name AS JobName,
    c.name AS Category,
    CAST(j.enabled AS bit) AS IsEnabled,

    CASE lh.run_status
        WHEN 0 THEN 'Failed'
        WHEN 1 THEN 'Succeeded'
        WHEN 2 THEN 'Retry'
        WHEN 3 THEN 'Cancelled'
        WHEN 4 THEN 'In Progress'
        ELSE 'Unknown'
    END AS CurrentStatus,

    msdb.dbo.agent_datetime(lh.run_date, lh.run_time) AS LastExecutionTime,

    (
        (lh.run_duration / 10000) * 3600 +
        ((lh.run_duration % 10000) / 100) * 60 +
        (lh.run_duration % 100)
    ) AS LastDurationSeconds,

    lh.message AS FailureMessage,

    CASE
        WHEN lh.run_status = 1 THEN CAST(1 AS bit)
        ELSE CAST(0 AS bit)
    END AS IsHealthy,

    j.description AS JobDescription,

    SUSER_SNAME(j.owner_sid) AS JobOwner,

    @@SERVERNAME AS ServerName

FROM msdb.dbo.sysjobs j
LEFT JOIN LatestJobHistory lh
    ON j.job_id = lh.job_id
   AND lh.rn = 1
LEFT JOIN msdb.dbo.syscategories c
    ON j.category_id = c.category_id;
GO