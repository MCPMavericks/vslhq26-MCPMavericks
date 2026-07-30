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

    public async Task<SqlAgentJob?> GetJobStatusByIdAsync(Guid jobId)
    {
        var response = await httpClient.GetFromJsonAsync<DabResponse<DabJobStatus>>(
            $"/api/JobStatus/JobId/{jobId}", JsonOptions);

        var r = response?.Value.FirstOrDefault();
        if (r is null) return null;

        return new SqlAgentJob
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
        };
    }

    public async Task<List<ActionHistoryEntry>> GetActionHistoryAsync(string jobName, int maxRows = 50)
    {
        var encoded = Uri.EscapeDataString(jobName);
        var response = await httpClient.GetFromJsonAsync<DabResponse<DabActionHistory>>(
            $"/api/ActionHistory?$filter=JobName eq '{jobName}'&$first={maxRows}&$orderby=ExecutedDate desc",
            JsonOptions);

        return response?.Value
            .Select(r => new ActionHistoryEntry
            {
                ActionHistoryId = r.ActionHistoryId,
                JobName         = r.JobName,
                ErrorMessage    = r.ErrorMessage,
                RootCause       = r.RootCause,
                ActionName      = r.ActionName,
                ActionResult    = r.ActionResult,
                McpTool         = r.McpTool,
                ExecutedBy      = r.ExecutedBy,
                ExecutedDate    = r.ExecutedDate
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

