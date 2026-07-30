using McpMaverick.Models;
using McpMaverick.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace McpMaverick.Pages;

public class JobDetailsModel(SqlJobService jobService) : PageModel
{
    [BindProperty(SupportsGet = true)]
    public string JobName { get; set; } = string.Empty;

    public List<ActionHistoryEntry> ActionHistory { get; private set; } = [];
    public string? ErrorMessage { get; private set; }

    // Stats derived from action history
    public int TotalActions   => ActionHistory.Count;
    public int SuccessCount   => ActionHistory.Count(h => h.ActionResult == "Success");
    public int FailureCount   => ActionHistory.Count(h => h.ActionResult == "Failed");
    public int PendingCount   => ActionHistory.Count(h => h.ActionResult == "Pending Approval");

    public async Task<IActionResult> OnGetAsync()
    {
        if (string.IsNullOrWhiteSpace(JobName))
            return RedirectToPage("/Jobs");

        try
        {
            ActionHistory = await jobService.GetActionHistoryAsync(JobName, 100);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to load action history: {ex.Message}";
        }

        return Page();
    }
}
