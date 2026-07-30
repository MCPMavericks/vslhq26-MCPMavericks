namespace McpMaverick.Models;

public class ActionHistoryEntry
{
    public int ActionHistoryId { get; set; }
    public string JobName { get; set; } = string.Empty;
    public string? ErrorMessage { get; set; }
    public string? RootCause { get; set; }
    public string ActionName { get; set; } = string.Empty;
    public string ActionResult { get; set; } = string.Empty;
    public string? McpTool { get; set; }
    public string? ExecutedBy { get; set; }
    public DateTime ExecutedDate { get; set; }
}
