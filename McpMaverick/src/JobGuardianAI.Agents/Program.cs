using System.Reflection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using JobGuardianAI.Agents.Services;

var host = Host.CreateDefaultBuilder(args)
    .ConfigureAppConfiguration(config =>
    {
        // Host.CreateDefaultBuilder only auto-loads user-secrets when
        // DOTNET_ENVIRONMENT=Development, but this worker is usually run without
        // that set, so load them unconditionally instead (no-op if none exist).
        config.AddUserSecrets(Assembly.GetExecutingAssembly(), optional: true);
    })
    .ConfigureServices((context, services) =>
    {
        services.AddSingleton<JobActionTools>();
        services.AddSingleton<JobGuardianAgentProvider>();
        services.AddHostedService<JobAgentHostedService>();
    })
    .Build();

await host.RunAsync();
