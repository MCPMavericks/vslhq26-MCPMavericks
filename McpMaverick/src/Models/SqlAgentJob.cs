namespace McpMaverick.Models;

public class SqlAgentJob
{
    public string JobName { get; set; } = string.Empty;
    public bool IsEnabled { get; set; }
    public string LastRunStatus { get; set; } = "Never Run";
    public DateTime? LastRunDateTime { get; set; }
}
