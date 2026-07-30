using System.ComponentModel;
using MailKit.Net.Smtp;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using MimeKit;

namespace JobGuardianAI.Agents.Services;

// Callable AI functions the agent can invoke as remediation actions.
public class JobActionTools
{
    private readonly ILogger<JobActionTools> _logger;
    private readonly IConfiguration _configuration;
    private readonly string _dbaTeamEmail;

    public JobActionTools(ILogger<JobActionTools> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
        _dbaTeamEmail = configuration["Notifications:DbaTeamEmail"] ?? "dba-team@jobguardian.local";
    }

    [Description("Restarts a failed SQL Server Agent job by name via msdb.dbo.sp_start_job. Use this for failures whose KnowledgeBase entry has AutomationLevel 'Automatic'.")]
    public async Task<string> RetryJobAsync(
        [Description("The exact JobName of the SQL Agent job to restart, as returned by the JobStatus entity.")] string jobName)
    {
        var connectionString = _configuration["Sql:ConnectionString"];
        if (string.IsNullOrWhiteSpace(connectionString))
        {
            return "RetryJob failed: no SQL connection string is configured (Sql:ConnectionString).";
        }

        try
        {
            await using var connection = new SqlConnection(connectionString);
            await connection.OpenAsync();

            await using var command = new SqlCommand("EXEC msdb.dbo.sp_start_job @job_name = @jobName", connection);
            command.Parameters.AddWithValue("@jobName", jobName);
            await command.ExecuteNonQueryAsync();

            _logger.LogInformation("Requested restart of SQL Agent job '{job}'.", jobName);
            return $"Job '{jobName}' restart requested successfully.";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to restart SQL Agent job '{job}'.", jobName);
            return $"Failed to restart job '{jobName}': {ex.Message}";
        }
    }

    [Description("Sends an email to the DBA/support team about a job failure that needs human attention.")]
    public async Task<string> SendEmail(
        [Description("Recipient email address. If omitted, defaults to the DBA team distribution list.")] string? to,
        [Description("Email subject line.")] string subject,
        [Description("Email body: describe the failed job, root cause, and recommended action.")] string body)
    {
        var recipient = string.IsNullOrWhiteSpace(to) ? _dbaTeamEmail : to;

        var host = _configuration["Smtp:Host"] ?? "localhost";
        var port = _configuration.GetValue<int?>("Smtp:Port") ?? 2525;
        var fromAddress = _configuration["Smtp:FromAddress"] ?? "jobguardian@local.test";
        var fromName = _configuration["Smtp:FromName"] ?? "JobGuardianAI";

        var message = new MimeMessage();
        message.From.Add(new MailboxAddress(fromName, fromAddress));
        message.To.Add(MailboxAddress.Parse(recipient));
        message.Subject = subject;
        message.Body = new TextPart("plain") { Text = body };

        try
        {
            using var client = new SmtpClient();
            await client.ConnectAsync(host, port, MailKit.Security.SecureSocketOptions.None);
            await client.SendAsync(message);
            await client.DisconnectAsync(quit: true);

            _logger.LogInformation("Sent email to {recipient} - Subject: {subject}", recipient, subject);
            return $"Email sent successfully to '{recipient}'.";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send email to {recipient} via {host}:{port}.", recipient, host, port);
            return $"Failed to send email to '{recipient}': {ex.Message}";
        }
    }
}
