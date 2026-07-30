namespace McpMaverick.Services.Dtos;

/// <summary>DAB REST projection of the dbo.JobStatus view.</summary>
internal sealed record DabJobStatus(
    string    JobId,
    string    JobName,
    string?   CurrentStatus,
    DateTime? LastExecutionTime,
    int?      DurationSeconds,
    string?   ErrorMessage,
    int       IsFailed,
    int       IsEnabled,
    string?   ServerName);
