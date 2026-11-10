using System.Globalization;
using System.Net.Http.Headers;
using System.Text;

namespace Nafru.Email;

internal interface INafruHttp
{
    Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        object? query = null,
        object? body = null,
        string? idempotencyKey = null,
        CancellationToken cancellationToken = default);
}

internal sealed class NafruHttp : INafruHttp
{
    private const int BaseBackoffMs = 300;
    private const int MaxBackoffMs = 8000;
    /// <summary>Bozuk ya da kötü niyetli bir ara katman belleği tüketemesin.</summary>
    internal const int MaxResponseBytes = 10 * 1024 * 1024;

    /// <summary>Paylaşılan istemci: her <see cref="NafruEmail"/> için yeni <see cref="HttpClient"/> soket tüketir.</summary>
    /// <summary>API asla yönlendirmez; yönlendirme izlemek <c>Authorization</c>'ı başka bir sunucuya sızdırabilir.</summary>
    private static readonly HttpClient SharedClient = new(new SocketsHttpHandler
    {
        PooledConnectionLifetime = TimeSpan.FromMinutes(5),
        AllowAutoRedirect = false
    })
    {
        Timeout = System.Threading.Timeout.InfiniteTimeSpan
    };

    private readonly HttpClient _client;
    private readonly string _base;
    private readonly string? _apiKey;
    private readonly Func<CancellationToken, Task<string?>>? _authorize;
    private readonly int _maxRetries;
    private readonly TimeSpan _timeout;
    /// <summary>İstemci başına tek uyarı: bağlantı istemcileri aynı nesneyi paylaşır.</summary>
    private readonly DeprecationNotice _deprecation;

    /// <param name="authorize">Verilirse <paramref name="apiKey"/> yerine her denemede bundan alınan belirteç kullanılır (<c>null</c>: başlık yok).</param>
    public NafruHttp(string baseUrl, string? apiKey, HttpClient? client, int maxRetries, TimeSpan timeout,
        Func<CancellationToken, Task<string?>>? authorize = null, DeprecationNotice? deprecation = null)
    {
        _deprecation = deprecation ?? new DeprecationNotice();
        _client = client ?? SharedClient;
        _base = baseUrl.TrimEnd('/');
        _apiKey = apiKey;
        _maxRetries = maxRetries;
        _timeout = timeout;
        _authorize = authorize;
    }

    public NafruHttp WithAuthorize(Func<CancellationToken, Task<string?>> authorize) =>
        new(_base, null, _client, _maxRetries, _timeout, authorize, _deprecation);

    public static string SerializeQuery(object? query)
    {
        if (query is null) return "";
        var parts = new List<string>();
        foreach (var property in JsonSerializer.SerializeToElement(query, query.GetType(), Json.Options).EnumerateObject())
        {
            var value = property.Value.ValueKind switch
            {
                JsonValueKind.String => property.Value.GetString(),
                JsonValueKind.Number => property.Value.GetRawText(),
                JsonValueKind.True => "true",
                JsonValueKind.False => "false",
                _ => null
            };
            if (!string.IsNullOrEmpty(value)) parts.Add($"{Uri.EscapeDataString(property.Name)}={Uri.EscapeDataString(value)}");
        }
        return parts.Count > 0 ? "?" + string.Join("&", parts) : "";
    }

    /// <summary>
    /// <c>GET</c> ve <c>DELETE</c> yinelenebilir; <c>POST</c>/<c>PATCH</c> yalnız istek işlenmeden reddedildiyse (429) ya da <c>Idempotency-Key</c> taşıyorsa yinelenir:
    /// anahtarsız sunucu hatasında e-posta çift gidebilir.
    /// </summary>
    private static bool IsSafeToRetry(HttpMethod method, string? idempotencyKey) =>
        method == HttpMethod.Get || method == HttpMethod.Delete || idempotencyKey is not null;

    private static Task Backoff(int attempt, double? retryAfterSeconds, CancellationToken cancellationToken)
    {
        var wait = retryAfterSeconds is { } seconds ? seconds * 1000 : BaseBackoffMs * Math.Pow(2, attempt);
        return Task.Delay(TimeSpan.FromMilliseconds(Math.Min(wait, MaxBackoffMs)), cancellationToken);
    }

    public async Task<T> SendAsync<T>(
        HttpMethod method,
        string path,
        object? query = null,
        object? body = null,
        string? idempotencyKey = null,
        CancellationToken cancellationToken = default)
    {
        Security.RequireHeaderValue(idempotencyKey, nameof(idempotencyKey));
        var url = _base + path + SerializeQuery(query);
        var json = body is null ? null : Json.Serialize(body);
        var safe = IsSafeToRetry(method, idempotencyKey);

        for (var attempt = 0; ; attempt++)
        {
            var token = _authorize is null ? _apiKey : await _authorize(cancellationToken).ConfigureAwait(false);
            var last = attempt >= _maxRetries;

            using var request = new HttpRequestMessage(method, url);
            request.Headers.TryAddWithoutValidation("Accept", "application/json");
            request.Headers.TryAddWithoutValidation("User-Agent", NafruEmail.UserAgent);
            if (token is not null) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
            if (idempotencyKey is not null) request.Headers.TryAddWithoutValidation("Idempotency-Key", idempotencyKey);
            if (json is not null)
            {
                request.Content = new StringContent(json, Encoding.UTF8);
                request.Content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
            }

            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(_timeout);

            int status;
            string? reason;
            string text;
            double? retryAfter;
            try
            {
                using var response = await _client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, timeout.Token).ConfigureAwait(false);
                status = (int)response.StatusCode;
                reason = response.ReasonPhrase;
                retryAfter = ReadRetryAfter(response);
                _deprecation.Check(response);
                text = await ReadBodyAsync(response, status, timeout.Token).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            {
                if (!last && safe)
                {
                    await Backoff(attempt, null, cancellationToken).ConfigureAwait(false);
                    continue;
                }
                throw NafruException.Timeout(_timeout);
            }
            catch (HttpRequestException error)
            {
                if (!last && safe)
                {
                    await Backoff(attempt, null, cancellationToken).ConfigureAwait(false);
                    continue;
                }
                throw NafruException.Network(error.Message, error);
            }

            // Kullanıcının kendi HttpClient'ı yönlendirmeyi izlemiyorsa 3xx buraya gelir; asla izlenmez ve yinelenmez.
            if (status is >= 300 and < 400)
                throw new NafruException(status, "unexpected_redirect", $"Beklenmeyen yönlendirme (HTTP {status}); API yönlendirme yapmaz");

            if (status is >= 200 and < 300)
                return string.IsNullOrWhiteSpace(text) ? default! : JsonSerializer.Deserialize<T>(text, Json.Options)!;

            var failure = NafruException.Parse(status, reason, text, retryAfter);
            var retryable = status == 429 || (status >= 500 && safe);
            if (retryable && !last)
            {
                await Backoff(attempt, failure.RetryAfter, cancellationToken).ConfigureAwait(false);
                continue;
            }
            throw failure;
        }
    }

    private static async Task<string> ReadBodyAsync(HttpResponseMessage response, int status, CancellationToken cancellationToken)
    {
        if (response.Content.Headers.ContentLength > MaxResponseBytes) throw TooLarge(status);
        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken).ConfigureAwait(false);
        using var buffer = new MemoryStream();
        var chunk = new byte[81920];
        int read;
        while ((read = await stream.ReadAsync(chunk, cancellationToken).ConfigureAwait(false)) > 0)
        {
            if (buffer.Length + read > MaxResponseBytes) throw TooLarge(status);
            buffer.Write(chunk, 0, read);
        }
        return Encoding.UTF8.GetString(buffer.GetBuffer(), 0, (int)buffer.Length);
    }

    private static NafruException TooLarge(int status) =>
        new(status, "response_too_large", $"Yanıt gövdesi {MaxResponseBytes / (1024 * 1024)} MB sınırını aşıyor");

    private static double? ReadRetryAfter(HttpResponseMessage response) =>
        response.Headers.TryGetValues("Retry-After", out var values)
        && double.TryParse(values.FirstOrDefault(), NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds)
        && seconds >= 0
            ? seconds
            : null;
}

internal sealed class DeprecationNotice
{
    private int _warned;

    /// <summary>Sunucu <c>Deprecation</c> başlığı gönderirse bir kez uyarır; çağrıyı asla bozmaz.</summary>
    public void Check(HttpResponseMessage response)
    {
        if (!response.Headers.Contains("Deprecation") || Interlocked.Exchange(ref _warned, 1) == 1) return;
        var message = $"[nafru] Bu SDK sürümü (dotnet {NafruEmail.SdkVersion}) kullanımdan kaldırıldı; lütfen güncelleyin.";
        if (Header(response, "Sunset") is { } sunset) message += $" Son tarih: {sunset}";
        if (Header(response, "Link") is { } link)
        {
            var start = link.IndexOf('<');
            var end = link.IndexOf('>', start + 1);
            message += $" Ayrıntı: {(start >= 0 && end > start ? link[(start + 1)..end] : link)}";
        }
        Console.Error.WriteLine(message);
    }

    private static string? Header(HttpResponseMessage response, string name) =>
        response.Headers.TryGetValues(name, out var values) ? string.Join(", ", values) : null;
}
