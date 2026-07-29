using McpMaverick.Services;
using McpMaverick.Models;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace McpMaverick.Pages;

public class JobsModel(SqlJobService jobService) : PageModel
{
    public List<SqlAgentJob> Jobs { get; private set; } = [];
    public string? ErrorMessage { get; private set; }

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
