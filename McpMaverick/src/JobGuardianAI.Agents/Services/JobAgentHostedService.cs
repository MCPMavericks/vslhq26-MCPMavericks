using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace JobGuardianAI.Agents.Services;

public class JobAgentHostedService : BackgroundService
{
    private readonly ILogger<JobAgentHostedService> _logger;
    private readonly JobGuardianAgentProvider _agentProvider;
    private readonly TimeSpan _pollInterval;

    public JobAgentHostedService(ILogger<JobAgentHostedService> logger, JobGuardianAgentProvider agentProvider, IConfiguration configuration)
    {
        _logger = logger;
        _agentProvider = agentProvider;
        var pollSeconds = configuration.GetValue<int?>("Agent:PollIntervalSeconds") ?? 60;
        _pollInterval = TimeSpan.FromSeconds(pollSeconds);
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        _logger.LogInformation("JobAgentHostedService started with a {interval} poll interval.", _pollInterval);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var agent = await _agentProvider.GetAgentAsync(stoppingToken);
                var response = await RetryHelper.ExecuteAsync(
                    () => agent.RunAsync(
                        $"Current UTC time: {DateTime.UtcNow:O}. Check for failed SQL Agent jobs and remediate any that you find.",
                        cancellationToken: stoppingToken),
                    maxAttempts: 2,
                    initialDelay: TimeSpan.FromSeconds(5),
                    _logger,
                    "Running agent cycle",
                    stoppingToken);

                _logger.LogInformation("Agent cycle result: {result}", response.Text);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error while running job agent loop.");
            }

            await Task.Delay(_pollInterval, stoppingToken);
        }
    }
}
