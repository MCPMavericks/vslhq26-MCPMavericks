using McpMaverick.Models;
using McpMaverick.Services.Dtos;
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
            .Select(MapJobStatus)
            .ToList() ?? [];
    }

    public async Task<SqlAgentJob?> GetJobStatusByIdAsync(Guid jobId)
    {
        var response = await httpClient.GetFromJsonAsync<DabResponse<DabJobStatus>>(
            $"/api/JobStatus/JobId/{jobId}", JsonOptions);

        var r = response?.Value.FirstOrDefault();
        return r is null ? null : MapJobStatus(r);
    }

    public async Task<List<ActionHistoryEntry>> GetActionHistoryAsync(string jobName, int maxRows = 50)
    {
        var response = await httpClient.GetFromJsonAsync<DabResponse<DabActionHistory>>(
            $"/api/ActionHistory?$filter=JobName eq '{jobName}'&$first={maxRows}&$orderby=ExecutedDate desc",
            JsonOptions);

        return response?.Value
            .Select(MapActionHistory)
            .ToList() ?? [];
    }

    // ── Mapping helpers ──────────────────────────────────────────────────────

    private static SqlAgentJob MapJobStatus(DabJobStatus r) => new()
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

    private static ActionHistoryEntry MapActionHistory(DabActionHistory r) => new()
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
    };
}


