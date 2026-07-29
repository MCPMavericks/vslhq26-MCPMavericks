using McpMaverick.Models;
using System.Net.Http.Json;
using System.Text.Json;

namespace McpMaverick.Services;

public class SqlJobService(HttpClient httpClient)
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

    public async Task<List<SqlAgentJob>> GetJobsAsync()
    {
        var response = await httpClient.GetFromJsonAsync<DabResponse<DabJobStatus>>(
            "/api/JobStatus", JsonOptions);

        return response?.Value
            .Select(r => new SqlAgentJob
            {
                JobId               = Guid.Parse(r.JobId),
                JobName             = r.JobName,
                IsEnabled           = r.IsEnabled == 1,
                CurrentStatus       = r.CurrentStatus ?? "Unknown",
                LastExecutionTime   = r.LastExecutionTime,
                LastDurationSeconds = r.DurationSeconds,
                FailureMessage      = r.ErrorMessage,
                IsHealthy           = r.IsFailed == 0,
                ServerName          = r.ServerName
            })
            .ToList() ?? [];
    }

    public async Task<List<JobRunHistory>> GetJobRunHistoryAsync(string jobName, int maxRows = 50)
    {
        var encoded = Uri.EscapeDataString(jobName);
        var response = await httpClient.GetFromJsonAsync<DabResponse<DabActionHistory>>(
            $"/api/ActionHistory?$filter=JobName eq '{encoded}'&$first={maxRows}&$orderby=ExecutedDate desc",
            JsonOptions);

        return response?.Value
            .Select(r => new JobRunHistory
            {
                JobName         = r.JobName,
                StepId          = 0,
                StepName        = r.ActionName,
                RunStatus       = r.ActionResult,
                RunDateTime     = r.ExecutedDate,
                DurationSeconds = 0,
                Message         = r.ErrorMessage ?? string.Empty
            })
            .ToList() ?? [];
    }

    // DAB wraps all REST results in { "value": [...] }
    private sealed record DabResponse<T>(List<T> Value);

    private sealed record DabJobStatus(
        string JobId,
        string JobName,
        string? CurrentStatus,
        DateTime? LastExecutionTime,
        int? DurationSeconds,
        string? ErrorMessage,
        int IsFailed,
        int IsEnabled,
        string? ServerName);

    private sealed record DabActionHistory(
        int ActionHistoryId,
        string JobName,
        string? ErrorMessage,
        string? RootCause,
        string ActionName,
        string ActionResult,
        string? McpTool,
        string? ExecutedBy,
        DateTime ExecutedDate);
}

