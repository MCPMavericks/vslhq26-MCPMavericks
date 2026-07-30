using Microsoft.Extensions.Logging;

namespace JobGuardianAI.Agents.Services;

// Small retry-with-backoff helper for smoothing over transient failures
// (DAB not ready yet, a flaky Azure OpenAI call) within a single cycle,
// instead of waiting a full poll interval to try again.
public static class RetryHelper
{
    public static async Task<T> ExecuteAsync<T>(
        Func<Task<T>> action,
        int maxAttempts,
        TimeSpan initialDelay,
        ILogger logger,
        string operationName,
        CancellationToken ct)
    {
        var delay = initialDelay;
        for (var attempt = 1; ; attempt++)
        {
            try
            {
                return await action();
            }
            catch (Exception ex) when (attempt < maxAttempts)
            {
                logger.LogWarning(ex, "{operation} failed on attempt {attempt}/{maxAttempts}, retrying in {delay}.", operationName, attempt, maxAttempts, delay);
                await Task.Delay(delay, ct);
                delay *= 2;
            }
        }
    }
}
