using McpMaverick.Models;
using Microsoft.Data.SqlClient;

namespace McpMaverick.Services;

public class SqlJobService(IConfiguration configuration)
{
    private readonly string _connectionString = configuration.GetConnectionString("SqlServer")
        ?? throw new InvalidOperationException("Connection string 'SqlServer' not found.");

    private const string JobsQuery = """
        SELECT
            j.name                                          AS JobName,
            j.enabled                                       AS IsEnabled,
            CASE h.run_status
                WHEN 0 THEN 'Failed'
                WHEN 1 THEN 'Succeeded'
                WHEN 2 THEN 'Retry'
                WHEN 3 THEN 'Cancelled'
                WHEN 4 THEN 'In Progress'
                ELSE 'Never Run'
            END                                             AS LastRunStatus,
            CASE WHEN h.run_date IS NOT NULL
                THEN msdb.dbo.agent_datetime(h.run_date, h.run_time)
                ELSE NULL
            END                                             AS LastRunDateTime
        FROM msdb.dbo.sysjobs j
        LEFT JOIN (
            SELECT job_id, run_status, run_date, run_time,
                   ROW_NUMBER() OVER (PARTITION BY job_id ORDER BY run_date DESC, run_time DESC) AS rn
            FROM msdb.dbo.sysjobhistory
            WHERE step_id = 0
        ) h ON j.job_id = h.job_id AND h.rn = 1
        ORDER BY j.name;
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
                JobName = reader.GetString(0),
                IsEnabled = reader.GetByte(1) == 1,
                LastRunStatus = reader.GetString(2),
                LastRunDateTime = reader.IsDBNull(3) ? null : reader.GetDateTime(3)
            });
        }

        return jobs;
    }
}
