using McpMaverick.Models;
using McpMaverick.Services;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace McpMaverick.Pages;

public class JobsModel(SqlJobService jobService) : PageModel
{
    public List<SqlAgentJob> Jobs { get; private set; } = [];
    public string? ErrorMessage { get; private set; }

    // Summary stats
    public int TotalJobs    => Jobs.Count;
    public int HealthyJobs  => Jobs.Count(j => j.IsHealthy && j.IsEnabled);
    public int FailedJobs   => Jobs.Count(j => j.CurrentStatus == "Failed");
    public int RunningJobs  => Jobs.Count(j => j.CurrentStatus == "In Progress");
    public int DisabledJobs => Jobs.Count(j => !j.IsEnabled);

    public List<SqlAgentJob> RecentFailures => Jobs
        .Where(j => j.CurrentStatus == "Failed")
        .OrderByDescending(j => j.LastExecutionTime)
        .Take(5)
        .ToList();

    public async Task OnGetAsync()
    {
        try
        {
            Jobs = await jobService.GetJobsAsync();
        }
        catch (Exception ex)
        {
            ErrorMessage = $"Failed to load SQL Server Agent jobs: {ex.Message}";
        }
    }
}

