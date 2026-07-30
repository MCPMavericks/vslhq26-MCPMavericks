namespace McpMaverick.Services.Dtos;

/// <summary>
/// DAB wraps every REST response — including single primary-key lookups — in { "value": [...] }.
/// </summary>
internal sealed record DabResponse<T>(List<T> Value);
