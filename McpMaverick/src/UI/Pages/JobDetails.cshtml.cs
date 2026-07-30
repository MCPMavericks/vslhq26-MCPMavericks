using McpMaverick.Models;
using McpMaverick.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace McpMaverick.Pages;

public class JobDetailsModel(SqlJobService jobService) : PageModel
{
    [BindProperty(SupportsGet = true)]
    public string JobName { get; set; } = string.Empty;

    [BindProperty(SupportsGet = true)]
    public Guid? JobId { get; set; }

    public SqlAgentJob? Job { get; private set; }
    public List<ActionHistoryEntry> ActionHistory { get; private set; } = [];
    public string? ErrorMessage { get; private set; }

    // Stats derived from action history
    public int TotalActions => ActionHistory.Count;
    public int SuccessCount => ActionHistory.Count(h => h.ActionResult == "Success");
    public int FailureCount => ActionHistory.Count(h => h.ActionResult == "Failed");
    public int PendingCount => ActionHistory.Count(h => h.ActionResult == "Pending Approval");

    public async Task<IActionResult> OnGetAsync()
    {
        if (string.IsNullOrWhiteSpace(JobName))
            return RedirectToPage("/Jobs");

        try
        {
            var actionHistoryTask = jobService.GetActionHistoryAsync(JobName, 100);
            var jobStatusTask     = JobId.HasValue
                ? jobService.GetJobStatusByIdAsync(JobId.Value)
                : Task.FromResult<SqlAgentJob?>(null);

            await Task.WhenAll(actionHistoryTask, jobStatusTask);

            ActionHistory = await actionHistoryTask;
            Job           = await jobStatusTask;
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to load job details: {ex.Message}";
        }

        return Page();
    }
}
