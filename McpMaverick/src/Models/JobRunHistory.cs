namespace McpMaverick.Models;

public class JobRunHistory
{
    public string JobName { get; set; } = string.Empty;
    public int StepId { get; set; }
    public string StepName { get; set; } = string.Empty;
    public string RunStatus { get; set; } = string.Empty;
    public DateTime RunDateTime { get; set; }
    public int DurationSeconds { get; set; }
    public string Message { get; set; } = string.Empty;
}
