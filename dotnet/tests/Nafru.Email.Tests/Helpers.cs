using System.Net;
using System.Text;
using System.Text.Json;

namespace Nafru.Email.Tests;

public sealed record Call(HttpMethod Method, string Url, HttpRequestMessage Request, string? Body)
{
    public string? Header(string name) =>
        Request.Headers.TryGetValues(name, out var values) ? string.Join(",", values)
        : Request.Content?.Headers.TryGetValues(name, out var content) == true ? string.Join(",", content) : null;

    public JsonElement Json => JsonDocument.Parse(Body!).RootElement;
}

/// <summary>Sahte taşıma: <c>route</c> her çağrıya yanıt verir; çağrılar kaydedilir.</summary>
public sealed class MockHandler(Func<Call, Task<HttpResponseMessage>> route) : HttpMessageHandler
{
    public List<Call> Calls { get; } = [];

    protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
    {
        var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(cancellationToken);
        var call = new Call(request.Method, request.RequestUri!.AbsoluteUri, request, body);
        lock (Calls) Calls.Add(call);
        cancellationToken.ThrowIfCancellationRequested();
        return await route(call).WaitAsync(cancellationToken);
    }
}

public static class Fake
{
    public static HttpResponseMessage Json(object body, HttpStatusCode status = HttpStatusCode.OK, params (string, string)[] headers)
    {
        var response = new HttpResponseMessage(status)
        {
            Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
        };
        foreach (var (name, value) in headers) response.Headers.TryAddWithoutValidation(name, value);
        return response;
    }

    /// <summary>Yanıtları sırayla verir, sonuncuyu tekrarlar.</summary>
    public static (NafruEmail Nafru, MockHandler Handler) Setup(int maxRetries, params Func<HttpResponseMessage>[] responses)
    {
        var index = 0;
        var handler = new MockHandler(_ => Task.FromResult(responses[Math.Min(index++, responses.Length - 1)]()));
        var nafru = new NafruEmail("key_test", new NafruEmailOptions
        {
            BaseUrl = "https://api.test/",
            HttpClient = new HttpClient(handler),
            MaxRetries = maxRetries,
            DevOutbox = ""
        });
        return (nafru, handler);
    }
}
