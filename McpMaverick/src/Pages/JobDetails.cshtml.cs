using McpMaverick.Models;
using McpMaverick.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace McpMaverick.Pages;

public class JobDetailsModel(SqlJobService jobService) : PageModel
{
    [BindProperty(SupportsGet = true)]
    public string JobName { get; set; } = string.Empty;

    public List<JobRunHistory> History { get; private set; } = [];
    public string? ErrorMessage { get; private set; }

    // Stats derived from history
    public int TotalRuns     => History.Where(h => h.StepId == 0).Count();
    public int SuccessCount  => History.Count(h => h.StepId == 0 && h.RunStatus == "Succeeded");
    public int FailureCount  => History.Count(h => h.StepId == 0 && h.RunStatus == "Failed");
    public double? AvgDurationSeconds => History.Where(h => h.StepId == 0).Any()
        ? History.Where(h => h.StepId == 0).Average(h => (double)h.DurationSeconds)
        : null;

    public async Task<IActionResult> OnGetAsync()
    {
        if (string.IsNullOrWhiteSpace(JobName))
            return RedirectToPage("/Jobs");

        try
        {
            History = await jobService.GetJobRunHistoryAsync(JobName, 100);
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to load run history: {ex.Message}";
        }

        return Page();
    }
}
