using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace JobGuardianAI.Agents.Services;

public class JobAgentHostedService : BackgroundService
{
    private readonly ILogger<JobAgentHostedService> _logger;
    private readonly JobGuardianAgentProvider _agentProvider;

    public JobAgentHostedService(ILogger<JobAgentHostedService> logger, JobGuardianAgentProvider agentProvider)
    {
        _logger = logger;
        _agentProvider = agentProvider;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("JobAgentHostedService started.");

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var agent = await _agentProvider.GetAgentAsync(stoppingToken);
                var response = await agent.RunAsync(
                    "Check for failed SQL Agent jobs and remediate any that you find.",
                    cancellationToken: stoppingToken);

                _logger.LogInformation("Agent cycle result: {result}", response.Text);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error while running job agent loop.");
            }

            await Task.Delay(TimeSpan.FromSeconds(60), stoppingToken);
        }
    }
}
