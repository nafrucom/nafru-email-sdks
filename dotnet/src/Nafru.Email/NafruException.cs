namespace Nafru.Email;

/// <summary>422 yanıtındaki alan ayrıntısı.</summary>
public sealed record NafruFieldError(string Field, string Message, string? I18nTranslationKey = null);

/// <summary>
/// Her başarısız çağrının fırlattığı hata. <see cref="StatusCode"/> ağ hatalarında <c>null</c>'dır. <see cref="Name"/>, sunucunun hata adıdır
/// (<c>validation_error</c>, <c>rate_limit_exceeded</c>, <c>not_found</c>, …); ağ ve zaman aşımı için <c>application_error</c> / <c>timeout_error</c>.
/// </summary>
public sealed class NafruException : Exception
{
    public NafruException(
        int? statusCode,
        string name,
        string message,
        IReadOnlyList<NafruFieldError>? errors = null,
        double? retryAfter = null,
        Exception? innerException = null) : base(message, innerException)
    {
        StatusCode = statusCode;
        Name = name;
        Errors = errors;
        RetryAfter = retryAfter;
    }

    public int? StatusCode { get; }
    public string Name { get; }
    public IReadOnlyList<NafruFieldError>? Errors { get; }
    /// <summary><c>429</c> yanıtındaki <c>retry-after</c> (saniye).</summary>
    public double? RetryAfter { get; }

    private static readonly Dictionary<int, string> NamesByStatus = new()
    {
        [400] = "invalid_request",
        [401] = "unauthorized",
        [403] = "forbidden",
        [404] = "not_found",
        [409] = "conflict",
        [413] = "payload_too_large",
        [422] = "validation_error",
        [429] = "rate_limit_exceeded"
    };

    internal static NafruException Network(string message, Exception? inner = null) =>
        new(null, "application_error", message, innerException: inner);

    internal static NafruException Timeout(TimeSpan timeout) =>
        new(null, "timeout_error", $"İstek {timeout.TotalMilliseconds:0} ms içinde tamamlanmadı");

    /// <summary>Standart gövde (<c>statusCode</c>, <c>name</c>, <c>message</c>, <c>errors</c>) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde).</summary>
    internal static NafruException Parse(int status, string? reasonPhrase, string? body, double? retryAfter)
    {
        var fallbackName = NamesByStatus.GetValueOrDefault(status, "application_error");
        if (TryParseObject(body) is { } root && root.TryGetProperty("message", out var message) && message.ValueKind == JsonValueKind.String)
        {
            List<NafruFieldError>? errors = null;
            if (root.TryGetProperty("errors", out var list) && list.ValueKind == JsonValueKind.Array)
            {
                errors = list.EnumerateArray()
                    .Where(entry => entry.ValueKind == JsonValueKind.Object)
                    .Select(entry => new NafruFieldError(
                        StringOf(entry, "field") ?? "",
                        StringOf(entry, "message") ?? "",
                        StringOf(entry, "i18nTranslationKey")))
                    .ToList();
            }
            var statusCode = root.TryGetProperty("statusCode", out var code) && code.ValueKind == JsonValueKind.Number ? code.GetInt32() : status;
            return new NafruException(
                statusCode,
                StringOf(root, "name") ?? fallbackName,
                message.GetString()!,
                errors is { Count: > 0 } ? errors : null,
                retryAfter);
        }
        return new NafruException(status, fallbackName, string.IsNullOrEmpty(reasonPhrase) ? $"HTTP {status}" : reasonPhrase, retryAfter: retryAfter);
    }

    private static JsonElement? TryParseObject(string? body)
    {
        if (string.IsNullOrEmpty(body)) return null;
        try
        {
            var root = JsonDocument.Parse(body).RootElement;
            return root.ValueKind == JsonValueKind.Object ? root : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }

    private static string? StringOf(JsonElement element, string name) =>
        element.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.String ? value.GetString() : null;
}
