using System.Diagnostics;
using System.Reflection;
using Microsoft.Extensions.Configuration;

var configPath = Path.Combine(AppContext.BaseDirectory, "dab.config.json");
if (!File.Exists(configPath))
{
    Console.Error.WriteLine($"dab.config.json not found at '{configPath}'. Rebuild this project so it gets copied from the repo root.");
    return 1;
}

var configuration = new ConfigurationBuilder()
    .AddUserSecrets(Assembly.GetExecutingAssembly(), optional: true)
    .AddEnvironmentVariables()
    .Build();

var connectionString = configuration["Sql:ConnectionString"];
if (string.IsNullOrWhiteSpace(connectionString))
{
    Console.Error.WriteLine("Sql:ConnectionString is not configured. Set it via:");
    Console.Error.WriteLine("  dotnet user-secrets set \"Sql:ConnectionString\" \"<connection-string>\" --project McpMaverick/src/DabHost");
    return 1;
}

var startInfo = new ProcessStartInfo
{
    FileName = "dab",
    WorkingDirectory = AppContext.BaseDirectory,
    UseShellExecute = false,
};
startInfo.ArgumentList.Add("start");
startInfo.ArgumentList.Add("--config");
startInfo.ArgumentList.Add(configPath);

// dab.config.json references this via @env('DAB_SQL_CONNECTION_STRING') so the real
// connection string never has to live in that (committed) file.
startInfo.Environment["DAB_SQL_CONNECTION_STRING"] = connectionString;

using var process = new Process { StartInfo = startInfo };

void KillProcessTree()
{
    try
    {
        if (!process.HasExited)
        {
            process.Kill(entireProcessTree: true);
        }
    }
    catch
    {
        // Best-effort shutdown; nothing more we can do if this fails.
    }
}

Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    KillProcessTree();
};
AppDomain.CurrentDomain.ProcessExit += (_, _) => KillProcessTree();

try
{
    process.Start();
}
catch (System.ComponentModel.Win32Exception ex)
{
    Console.Error.WriteLine("Failed to start 'dab'. Make sure the Data API Builder CLI is installed and on PATH:");
    Console.Error.WriteLine("  dotnet tool install -g Microsoft.DataApiBuilder");
    Console.Error.WriteLine(ex.Message);
    return 1;
}

Console.WriteLine($"[DabHost] Started dab (pid {process.Id}) with config '{configPath}'.");
await process.WaitForExitAsync();
return process.ExitCode;
