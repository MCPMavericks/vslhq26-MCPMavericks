namespace McpMaverick.Models;

public class SqlAgentJob
{
    public Guid JobId { get; set; }
    public string JobName { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public bool IsEnabled { get; set; }
    public string CurrentStatus { get; set; } = "Unknown";
    public DateTime? LastExecutionTime { get; set; }
    public int? LastDurationSeconds { get; set; }
    public string? FailureMessage { get; set; }
    public bool IsHealthy { get; set; }
    public string? JobDescription { get; set; }
    public string? JobOwner { get; set; }
    public string? ServerName { get; set; }

    public string FormattedDuration => LastDurationSeconds.HasValue
        ? LastDurationSeconds.Value >= 60
            ? $"{LastDurationSeconds.Value / 60}m {LastDurationSeconds.Value % 60}s"
            : $"{LastDurationSeconds.Value}s"
        : "—";
}
