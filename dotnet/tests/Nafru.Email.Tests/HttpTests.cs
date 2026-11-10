using System.Net;

namespace Nafru.Email.Tests;

public class HttpTests
{
    [Fact]
    public async Task Send_ShipsAuthUserAgentJsonAndIdempotencyKey()
    {
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(new { id = "e1" }));
        var result = await nafru.Emails.SendAsync(
            new SendEmailInput { From = "a@x.test", To = ["b@x.test"], Subject = "s", Text = "t", ReplyTo = ["r@x.test"] },
            idempotencyKey: "k-1");
        Assert.Equal("e1", result.Id);
        var call = handler.Calls[0];
        Assert.Equal("https://api.test/emails", call.Url);
        Assert.Equal(HttpMethod.Post, call.Method);
        Assert.Equal("Bearer key_test", call.Header("Authorization"));
        Assert.Equal("application/json", call.Header("Content-Type"));
        Assert.Equal("nafru-email-dotnet/" + NafruEmail.SdkVersion, call.Header("User-Agent"));
        Assert.Equal("k-1", call.Header("Idempotency-Key"));
        Assert.Equal("""{"from":"a@x.test","to":["b@x.test"],"reply_to":["r@x.test"],"subject":"s","text":"t"}""", call.Body);
    }

    [Fact]
    public async Task Query_CarriesOnlyFilledValues()
    {
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(new { @object = "list", data = Array.Empty<object>(), has_more = false }));
        await nafru.Contacts.ListAsync(new ListContactsQuery { Limit = 5, After = null, Search = "ali" });
        await nafru.Events.ListAsync(new ListEventsQuery { Email = "a@x.test", Name = "" });
        Assert.Equal("https://api.test/contacts?limit=5&search=ali", handler.Calls[0].Url);
        Assert.Equal("https://api.test/events?email=a%40x.test", handler.Calls[1].Url);
    }

    [Fact]
    public async Task ErrorBody_IsParsed()
    {
        var (nafru, _) = Fake.Setup(0, () => Fake.Json(new
        {
            statusCode = 422,
            name = "validation_error",
            message = "Geçersiz",
            errors = new[] { new { field = "to", message = "zorunlu", i18nTranslationKey = "k" } }
        }, HttpStatusCode.UnprocessableEntity));
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.SendAsync(new SendEmailInput { To = ["x"], Text = "t" }));
        Assert.Equal(422, error.StatusCode);
        Assert.Equal("validation_error", error.Name);
        Assert.Equal("Geçersiz", error.Message);
        Assert.Equal(new NafruFieldError("to", "zorunlu", "k"), Assert.Single(error.Errors!));
    }

    [Fact]
    public async Task NonStandardBody_BuildsErrorFromStatus()
    {
        var (nafru, _) = Fake.Setup(0, () => new HttpResponseMessage(HttpStatusCode.BadGateway)
        {
            ReasonPhrase = "Bad Gateway",
            Content = new StringContent("<html>bad gateway</html>")
        });
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.GetAsync("e1"));
        Assert.Equal((502, "application_error", "Bad Gateway"), (error.StatusCode!.Value, error.Name, error.Message));
    }

    [Fact]
    public async Task NetworkError_HasNullStatus()
    {
        var (nafru, _) = Fake.Setup(0, () => throw new HttpRequestException("fetch failed"));
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.SendAsync(new SendEmailInput { To = ["x"], Text = "t" }));
        Assert.Null(error.StatusCode);
        Assert.Equal(("application_error", "fetch failed"), (error.Name, error.Message));
    }

    private static HttpResponseMessage Limited() =>
        Fake.Json(new { statusCode = 429, name = "rate_limit_exceeded", message = "yavaş" }, HttpStatusCode.TooManyRequests, ("Retry-After", "0"));

    [Fact]
    public async Task RateLimit_RetriedWithRetryAfter_EvenForPost()
    {
        var (nafru, handler) = Fake.Setup(2, Limited, () => Fake.Json(new { id = "e1" }));
        var result = await nafru.Emails.SendAsync(new SendEmailInput { To = ["x"], Text = "t" });
        Assert.Equal("e1", result.Id);
        Assert.Equal(2, handler.Calls.Count);
    }

    [Fact]
    public async Task RateLimit_ExhaustedThrowsWithRetryAfter()
    {
        var (nafru, handler) = Fake.Setup(1, Limited);
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.GetAsync("e1"));
        Assert.Equal((429, "rate_limit_exceeded", 0d), (error.StatusCode!.Value, error.Name, error.RetryAfter!.Value));
        Assert.Equal(2, handler.Calls.Count);
    }

    private static HttpResponseMessage Down() =>
        Fake.Json(new { statusCode = 500, name = "application_error", message = "x" }, HttpStatusCode.InternalServerError);

    [Fact]
    public async Task ServerError_GetRetried_PostWithoutKeyNot()
    {
        var get = Fake.Setup(1, Down, () => Fake.Json(new { id = "e1" }));
        Assert.Equal("e1", (await get.Nafru.Emails.GetAsync("e1")).Id);
        Assert.Equal(2, get.Handler.Calls.Count);

        var post = Fake.Setup(1, Down, () => Fake.Json(new { id = "e1" }));
        var error = await Assert.ThrowsAsync<NafruException>(() => post.Nafru.Emails.SendAsync(new SendEmailInput { To = ["x"], Text = "t" }));
        Assert.Equal(500, error.StatusCode);
        Assert.Single(post.Handler.Calls);
    }

    [Fact]
    public async Task ServerError_PostWithIdempotencyKeyRetried()
    {
        var (nafru, handler) = Fake.Setup(1, Down, () => Fake.Json(new { id = "e1" }));
        var result = await nafru.Emails.SendAsync(new SendEmailInput { To = ["x"], Text = "t" }, "k-1");
        Assert.Equal("e1", result.Id);
        Assert.Equal("k-1", handler.Calls[1].Header("Idempotency-Key"));
    }

    [Fact]
    public async Task Timeout_ThrowsTimeoutError()
    {
        var handler = new MockHandler(async _ =>
        {
            await Task.Delay(Timeout.Infinite);
            return new HttpResponseMessage();
        });
        var nafru = new NafruEmail("k", new NafruEmailOptions
        {
            BaseUrl = "https://api.test", MaxRetries = 0, Timeout = TimeSpan.FromMilliseconds(20), HttpClient = new HttpClient(handler)
        });
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.GetAsync("e1"));
        Assert.Equal((null, "timeout_error"), (error.StatusCode, error.Name));
    }

    // NAFRU_API_KEY süreç geneli: ona dokunan testler aynı sınıfta (sırayla) çalışır.
    [Fact]
    public async Task ApiKeyRequired_BaseUrlDefaultsToProduction()
    {
        var previous = Environment.GetEnvironmentVariable("NAFRU_API_KEY");
        Environment.SetEnvironmentVariable("NAFRU_API_KEY", null);
        try
        {
            Assert.Contains("apiKey", Assert.Throws<ArgumentException>(() => new NafruEmail()).Message);
            Assert.Contains("apiKey", Assert.Throws<ArgumentException>(() => new NafruEmail("")).Message);
        }
        finally
        {
            Environment.SetEnvironmentVariable("NAFRU_API_KEY", previous);
        }
        foreach (var baseUrl in new[] { null, "" })
        {
            var handler = new MockHandler(_ => Task.FromResult(Fake.Json(new { id = "e1" })));
            var nafru = new NafruEmail("k", new NafruEmailOptions { BaseUrl = baseUrl, HttpClient = new HttpClient(handler) });
            await nafru.Emails.GetAsync("e1");
            Assert.Equal("https://email.nafru.com/api/emails/e1", handler.Calls[0].Url);
        }
    }

    [Fact]
    public async Task ApiKeyOmitted_ReadFromEnvironment()
    {
        var previous = Environment.GetEnvironmentVariable("NAFRU_API_KEY");
        Environment.SetEnvironmentVariable("NAFRU_API_KEY", "nafru_env");
        try
        {
            var handler = new MockHandler(_ => Task.FromResult(Fake.Json(new { id = "e1" })));
            var nafru = new NafruEmail(null, new NafruEmailOptions { HttpClient = new HttpClient(handler) });
            await nafru.Emails.GetAsync("e1");
            Assert.Equal("Bearer nafru_env", handler.Calls[0].Header("Authorization"));
            Assert.NotNull(new NafruEmail());
        }
        finally
        {
            Environment.SetEnvironmentVariable("NAFRU_API_KEY", previous);
        }
    }

    [Fact]
    public async Task Deprecation_WarnsOncePerClient_NeverFails()
    {
        var (nafru, _) = Fake.Setup(0, () => Fake.Json(new { id = "e1" }, HttpStatusCode.OK,
            ("Deprecation", "true"), ("Sunset", "Wed, 31 Mar 2027 00:00:00 GMT"), ("Link", "<https://nafru.com/sdk>; rel=\"deprecation\"")));
        var previous = Console.Error;
        var output = new StringWriter();
        Console.SetError(output);
        try
        {
            await nafru.Emails.GetAsync("e1");
            await nafru.Emails.GetAsync("e1");
        }
        finally
        {
            Console.SetError(previous);
        }
        Assert.Equal(
            $"[nafru] Bu SDK sürümü (dotnet {NafruEmail.SdkVersion}) kullanımdan kaldırıldı; lütfen güncelleyin. Son tarih: Wed, 31 Mar 2027 00:00:00 GMT Ayrıntı: https://nafru.com/sdk"
            + Environment.NewLine,
            output.ToString());
    }
}
