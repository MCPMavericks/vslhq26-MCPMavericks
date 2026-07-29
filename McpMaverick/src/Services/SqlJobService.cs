using McpMaverick.Models;
using Microsoft.Data.SqlClient;

namespace McpMaverick.Services;

public class SqlJobService(IConfiguration configuration)
{
    private readonly string _connectionString = configuration.GetConnectionString("SqlServer")
        ?? throw new InvalidOperationException("Connection string 'SqlServer' not found.");

    private const string JobsQuery = """
        SELECT
            JobId,
            JobName,
            Category,
            IsEnabled,
            CurrentStatus,
            LastExecutionTime,
            LastDurationSeconds,
            FailureMessage,
            IsHealthy,
            JobDescription,
            JobOwner,
            ServerName
        FROM dbo.JobExecutionStatus
        ORDER BY JobName;
        """;

    private const string HistoryQuery = """
        SELECT
            j.name                                                          AS JobName,
            h.step_id                                                       AS StepId,
            h.step_name                                                     AS StepName,
            CASE h.run_status
                WHEN 0 THEN 'Failed'
                WHEN 1 THEN 'Succeeded'
                WHEN 2 THEN 'Retry'
                WHEN 3 THEN 'Cancelled'
                WHEN 4 THEN 'In Progress'
                ELSE 'Unknown'
            END                                                             AS RunStatus,
            msdb.dbo.agent_datetime(h.run_date, h.run_time)                AS RunDateTime,
            (h.run_duration / 10000)        * 3600 +
            ((h.run_duration % 10000) / 100) * 60  +
            (h.run_duration % 100)                                          AS DurationSeconds,
            h.message                                                       AS Message
        FROM msdb.dbo.sysjobhistory h
        JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
        WHERE j.name = @JobName
        ORDER BY h.run_date DESC, h.run_time DESC, h.step_id;
        """;

    public async Task<List<SqlAgentJob>> GetJobsAsync()
    {
        var jobs = new List<SqlAgentJob>();

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync();

        await using var command = new SqlCommand(JobsQuery, connection);
        await using var reader = await command.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            jobs.Add(new SqlAgentJob
            {
                JobId             = reader.GetGuid(0),
                JobName           = reader.GetString(1),
                Category          = reader.IsDBNull(2) ? string.Empty : reader.GetString(2),
                IsEnabled         = reader.GetBoolean(3),
                CurrentStatus     = reader.IsDBNull(4) ? "Unknown" : reader.GetString(4),
                LastExecutionTime = reader.IsDBNull(5) ? null : reader.GetDateTime(5),
                LastDurationSeconds = reader.IsDBNull(6) ? null : reader.GetInt32(6),
                FailureMessage    = reader.IsDBNull(7) ? null : reader.GetString(7),
                IsHealthy         = !reader.IsDBNull(8) && reader.GetBoolean(8),
                JobDescription    = reader.IsDBNull(9) ? null : reader.GetString(9),
                JobOwner          = reader.IsDBNull(10) ? null : reader.GetString(10),
                ServerName        = reader.IsDBNull(11) ? null : reader.GetString(11)
            });
        }

        return jobs;
    }

    public async Task<List<JobRunHistory>> GetJobRunHistoryAsync(string jobName, int maxRows = 50)
    {
        var history = new List<JobRunHistory>();

        await using var connection = new SqlConnection(_connectionString);
        await connection.OpenAsync();

        var sql = HistoryQuery.Replace(";", $"\nORDER BY (SELECT NULL)") // re-use ordering already defined
            .Replace("ORDER BY h.run_date DESC, h.run_time DESC, h.step_id;",
                     $"ORDER BY h.run_date DESC, h.run_time DESC, h.step_id\nOFFSET 0 ROWS FETCH NEXT {maxRows} ROWS ONLY;");

        await using var command = new SqlCommand(sql, connection);
        command.Parameters.AddWithValue("@JobName", jobName);
        await using var reader = await command.ExecuteReaderAsync();

        while (await reader.ReadAsync())
        {
            history.Add(new JobRunHistory
            {
                JobName         = reader.GetString(0),
                StepId          = reader.GetInt32(1),
                StepName        = reader.GetString(2),
                RunStatus       = reader.GetString(3),
                RunDateTime     = reader.GetDateTime(4),
                DurationSeconds = reader.GetInt32(5),
                Message         = reader.IsDBNull(6) ? string.Empty : reader.GetString(6)
            });
        }

        return history;
    }
}

