using System.ClientModel;
using Microsoft.Agents.AI;
using Microsoft.Extensions.AI;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Client;
using OpenAI;
using OpenAI.Chat;

namespace JobGuardianAI.Agents.Services;

// Builds (once) and caches the AIAgent that ties together the Azure OpenAI model,
// DAB's MCP tools (describe_entities/read_records/create_record/...), and the
// local RetryJob/SendEmail action tools.
public class JobGuardianAgentProvider : IAsyncDisposable
{
    private static string BuildInstructions(int retryCooldownMinutes) => $$"""
        You are JobGuardianAI, an autonomous SQL Server Agent job monitoring assistant.

        Data is reachable only through the DAB MCP tools (describe_entities, read_records,
        create_record, ...). Always call describe_entities before using an entity for the
        first time in a session, so you know its real field names.

        Each run starts with the current UTC time in the user message - use it to reason
        about how long ago past actions happened.

        On every run, follow this procedure:
        1. Use read_records on the "JobStatus" entity to find jobs where IsFailed = 1.
        2. If there are no failed jobs, reply briefly that everything is healthy and stop -
           do not call any other tools.
        3. For each failed job, use read_records on the "ActionHistory" entity filtered by
           JobName, ordered by ExecutedDate descending, to see what has already been done for
           it. This is your memory - never act on a job without checking this first.
           IMPORTANT: JobStatus.LastExecutionTime is in the SQL Server's LOCAL time zone, not
           UTC. Always use LastExecutionTimeUtc instead - never LastExecutionTime.
           Find the ActionHistory entries whose JobLastExecutionTimeUtc EXACTLY equals this
           job's current LastExecutionTimeUtc - these are prior actions for this exact run
           (not some earlier failure of the same job).
           - If none exist, this run has never been handled - go to step 4 immediately.
           - If some exist and the most recent one's ExecutedDate is less than
             {{retryCooldownMinutes}} minutes ago, you are in the cooldown window - skip this
             job for now, it will be reconsidered once the cooldown elapses.
           - If some exist and the most recent one is {{retryCooldownMinutes}}+ minutes old,
             the cooldown has elapsed and this still-failing run is eligible to be handled
             again - go to step 4.
        4. Use read_records on the "KnowledgeBase" entity (IsActive = 1) and find the entry
           whose ErrorPattern is a case-insensitive substring of the job's ErrorMessage. If
           more than one matches, pick the one with the highest Confidence.
        5. Decide the action, counting only prior ActionHistory entries for this exact run
           (matched by JobLastExecutionTimeUtc as in step 3):
           - If the matched entry's AutomationLevel is "Automatic" AND fewer than 2 prior
             "Retry Job" attempts exist for this exact run, call RetryJobAsync with the job's
             JobName.
           - Otherwise - AutomationLevel is "Approval"/"Manual", or this exact run has already
             had 2 retry attempts without resolving, or no KnowledgeBase entry matched - call
             SendEmail summarizing the job name, error, root cause, and recommended action, so
             a human can fix the underlying cause (e.g. a missing file or bad data). Leave "to"
             empty to use the default DBA team address.
           Note: once you fix the underlying cause and the job runs again (whether triggered
           by you, its own schedule, or a RetryJobAsync call), LastExecutionTimeUtc changes and
           this job is evaluated completely fresh from step 3 - there is no permanent lockout.
        6. After acting on a job, call create_record on the "ActionHistory" entity with fields:
           JobName, ErrorMessage, RootCause (from the matched entry, or null if none matched),
           ActionName (short label such as "Retry Job", "Notify DBA", or "Investigate"),
           ActionResult (a short outcome word, under 50 characters, such as "Success",
           "Failed", "Notified", or "Pending Approval" - base it on what the tool call actually
           returned, don't assume success), McpTool (the KnowledgeBase entry's McpTool value,
           or the tool you called), ExecutedBy = "JobGuardianAI.Agents", and
           JobLastExecutionTimeUtc = this job's current LastExecutionTimeUtc (required - this
           is how future runs know this exact failure was already handled).
        7. Summarize what you found and did (including anything skipped due to already being
           handled or still in cooldown, and why) in a short final reply.
        """;

    private readonly IConfiguration _configuration;
    private readonly ILoggerFactory _loggerFactory;
    private readonly ILogger<JobGuardianAgentProvider> _logger;
    private readonly JobActionTools _actionTools;
    private readonly SemaphoreSlim _initLock = new(1, 1);
    private McpClient? _mcpClient;
    private AIAgent? _agent;

    public JobGuardianAgentProvider(IConfiguration configuration, ILoggerFactory loggerFactory, ILogger<JobGuardianAgentProvider> logger, JobActionTools actionTools)
    {
        _configuration = configuration;
        _loggerFactory = loggerFactory;
        _logger = logger;
        _actionTools = actionTools;
    }

    public async Task<AIAgent> GetAgentAsync(CancellationToken ct)
    {
        if (_agent is not null)
        {
            return _agent;
        }

        await _initLock.WaitAsync(ct);
        try
        {
            if (_agent is not null)
            {
                return _agent;
            }

            try
            {
                var mcpUrl = _configuration["Dab:McpUrl"] ?? "http://localhost:5000/mcp";

                var mcpTools = await RetryHelper.ExecuteAsync(async () =>
                {
                    // Recreate the transport/client on every attempt - a failed
                    // McpClient.CreateAsync call leaves nothing reusable behind.
                    var transport = new HttpClientTransport(new HttpClientTransportOptions
                    {
                        Endpoint = new Uri(mcpUrl),
                        Name = "JobGuardianDab"
                    }, _loggerFactory);

                    _mcpClient = await McpClient.CreateAsync(transport, loggerFactory: _loggerFactory, cancellationToken: ct);
                    return await _mcpClient.ListToolsAsync(cancellationToken: ct);
                }, maxAttempts: 4, initialDelay: TimeSpan.FromSeconds(3), _logger, "Connecting to DAB's MCP endpoint", ct);

                var endpoint = _configuration["AzureOpenAI:Endpoint"]
                    ?? throw new InvalidOperationException("AzureOpenAI:Endpoint is not configured.");
                var deployment = _configuration["AzureOpenAI:DeploymentName"];
                if (string.IsNullOrWhiteSpace(deployment))
                {
                    throw new InvalidOperationException("AzureOpenAI:DeploymentName is not configured. Set it via appsettings.json or `dotnet user-secrets set AzureOpenAI:DeploymentName <name>`.");
                }

                var apiKey = _configuration["AzureOpenAI:ApiKey"];
                if (string.IsNullOrWhiteSpace(apiKey))
                {
                    throw new InvalidOperationException("AzureOpenAI:ApiKey is not configured. Set it via `dotnet user-secrets set AzureOpenAI:ApiKey <key>` - do not put it in appsettings.json.");
                }

                var retryCooldownMinutes = _configuration.GetValue<int?>("Agent:RetryCooldownMinutes") ?? 5;

                // Azure AI Foundry resources (services.ai.azure.com/openai/v1) speak the plain
                // OpenAI v1 API, so we point the OpenAI SDK's ChatClient at that endpoint directly
                // rather than going through AzureOpenAIClient (which targets the older
                // *.openai.azure.com surface).
                var chatClient = new ChatClient(deployment, new ApiKeyCredential(apiKey), new OpenAIClientOptions
                {
                    Endpoint = new Uri(endpoint)
                });

                var tools = new List<AITool>(mcpTools)
                {
                    AIFunctionFactory.Create(_actionTools.RetryJobAsync),
                    AIFunctionFactory.Create(_actionTools.SendEmail)
                };

                _agent = chatClient.AsAIAgent(
                    instructions: BuildInstructions(retryCooldownMinutes),
                    name: "JobGuardianAI",
                    tools: tools,
                    loggerFactory: _loggerFactory);

                return _agent;
            }
            catch
            {
                // Setup failed partway through - don't leave a half-built MCP client
                // behind for the next attempt to silently leak.
                if (_mcpClient is not null)
                {
                    await _mcpClient.DisposeAsync();
                    _mcpClient = null;
                }

                throw;
            }
        }
        finally
        {
            _initLock.Release();
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (_mcpClient is not null)
        {
            await _mcpClient.DisposeAsync();
        }
    }
}
