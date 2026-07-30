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
    private const string Instructions = """
        You are JobGuardianAI, an autonomous SQL Server Agent job monitoring assistant.

        Data is reachable only through the DAB MCP tools (describe_entities, read_records,
        create_record, ...). Always call describe_entities before using an entity for the
        first time in a session, so you know its real field names.

        On every run, follow this procedure:
        1. Use read_records on the "JobStatus" entity to find jobs where IsFailed = 1.
        2. If there are no failed jobs, reply briefly that everything is healthy and stop -
           do not call any other tools.
        3. For each failed job, use read_records on the "KnowledgeBase" entity (IsActive = 1)
           and find the entry whose ErrorPattern is a case-insensitive substring of the job's
           ErrorMessage. If more than one matches, pick the one with the highest Confidence.
        4. Decide the action from the matched entry's AutomationLevel:
           - "Automatic": call the RetryJobAsync tool with the job's JobName.
           - "Approval" or "Manual": call the SendEmail tool, summarizing the job name, error,
             root cause, and recommended action. Leave "to" empty to use the default DBA team address.
           - If no KnowledgeBase entry matches, call SendEmail to ask a human to investigate.
        5. After acting on a job, call create_record on the "ActionHistory" entity with fields:
           JobName, ErrorMessage, RootCause (from the matched entry, or null if none matched),
           ActionName (short label such as "Retry Job", "Notify DBA", or "Investigate"),
           ActionResult (a short outcome word, under 50 characters, such as "Success",
           "Failed", "Notified", or "Pending Approval" - base it on what the tool call actually
           returned, don't assume success), McpTool (the KnowledgeBase entry's McpTool value,
           or the tool you called), and ExecutedBy = "JobGuardianAI.Agents".
        6. Summarize what you found and did in a short final reply.
        """;

    private readonly IConfiguration _configuration;
    private readonly ILoggerFactory _loggerFactory;
    private readonly JobActionTools _actionTools;
    private readonly SemaphoreSlim _initLock = new(1, 1);
    private McpClient? _mcpClient;
    private AIAgent? _agent;

    public JobGuardianAgentProvider(IConfiguration configuration, ILoggerFactory loggerFactory, JobActionTools actionTools)
    {
        _configuration = configuration;
        _loggerFactory = loggerFactory;
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

            var mcpUrl = _configuration["Dab:McpUrl"] ?? "http://localhost:5000/mcp";
            var transport = new HttpClientTransport(new HttpClientTransportOptions
            {
                Endpoint = new Uri(mcpUrl),
                Name = "JobGuardianDab"
            }, _loggerFactory);

            _mcpClient = await McpClient.CreateAsync(transport, loggerFactory: _loggerFactory, cancellationToken: ct);
            var mcpTools = await _mcpClient.ListToolsAsync(cancellationToken: ct);

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
                instructions: Instructions,
                name: "JobGuardianAI",
                tools: tools,
                loggerFactory: _loggerFactory);

            return _agent;
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
