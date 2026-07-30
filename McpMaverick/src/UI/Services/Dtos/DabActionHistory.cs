namespace McpMaverick.Services.Dtos;

/// <summary>DAB REST projection of the dbo.ActionHistory table.</summary>
internal sealed record DabActionHistory(
    int       ActionHistoryId,
    string    JobName,
    string?   ErrorMessage,
    string?   RootCause,
    string    ActionName,
    string    ActionResult,
    string?   McpTool,
    string?   ExecutedBy,
    DateTime  ExecutedDate);
