using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Nafru.Email.Tests;

public class AppTests
{
    private static (NafruConnect Nafru, MockHandler Handler) Server(Func<Call, Task<HttpResponseMessage>> route)
    {
        var handler = new MockHandler(route);
        var nafru = new NafruConnect(new NafruConnectOptions
        {
            ClientId = "app_x",
            ClientSecret = "nfs_secret",
            BaseUrl = "https://api.test/",
            WebUrl = "https://web.test",
            HttpClient = new HttpClient(handler),
            MaxRetries = 0,
            DevOutbox = ""
        });
        return (nafru, handler);
    }

    private static HttpResponseMessage Token(int n) => Fake.Json(new
    {
        access_token = $"nfa_{n}", refresh_token = $"nfr_{n}", token_type = "Bearer", expires_in = 3600, connection_id = "conn_1", scopes = new[] { "emails.send" }
    });

    private static HttpResponseMessage GrantError() =>
        Fake.Json(new { statusCode = 400, name = "invalid_grant", message = "invalid" }, HttpStatusCode.BadRequest);

    private static bool IsToken(Call call) => call.Url.EndsWith("/oauth/token");
    private static IEnumerable<Call> Api(MockHandler handler) => handler.Calls.Where(call => !call.Url.Contains("/oauth/"));
    private static Dictionary<string, string> Query(string url) =>
        new Uri(url).Query.TrimStart('?').Split('&').Select(p => p.Split('=')).ToDictionary(p => p[0], p => Uri.UnescapeDataString(p[1]));

    [Fact]
    public void Pkce_VerifierAndS256Challenge()
    {
        var (verifier, challenge) = NafruConnect.CreatePkce();
        Assert.Matches("^[A-Za-z0-9_-]{43}$", verifier);
        var expected = Convert.ToBase64String(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        Assert.Equal(expected, challenge);
        Assert.NotEqual(verifier, NafruConnect.CreatePkce().Verifier);
    }

    [Fact]
    public void AuthorizeUrl_BuildsConsentUrl_StateAndScopesRequired()
    {
        var (nafru, _) = Server(_ => Task.FromResult(Fake.Json(new { })));
        var result = nafru.AuthorizeUrl(new AuthorizeUrlInput
        {
            RedirectUri = "https://scout.test/cb", State = "st1", Scopes = [AppScope.EmailsSend, AppScope.TemplatesRead], LoginHint = "a@b.co"
        });
        Assert.StartsWith("https://web.test/connect?", result.Url);
        var query = Query(result.Url);
        Assert.Equal("app_x", query["client_id"]);
        Assert.Equal("https://scout.test/cb", query["redirect_uri"]);
        Assert.Equal("st1", query["state"]);
        Assert.Equal("emails.send templates.read", query["scope"]);
        Assert.Equal("S256", query["code_challenge_method"]);
        Assert.Equal("a@b.co", query["login_hint"]);
        Assert.Matches("^[A-Za-z0-9_-]{43}$", query["code_challenge"]);
        Assert.Matches("^[A-Za-z0-9_-]{43}$", result.CodeVerifier);
        Assert.Throws<ArgumentException>(() => nafru.AuthorizeUrl(new AuthorizeUrlInput { RedirectUri = "x", State = "", Scopes = ["emails.send"] }));
        Assert.Throws<ArgumentException>(() => nafru.AuthorizeUrl(new AuthorizeUrlInput { RedirectUri = "x", State = "s", Scopes = [] }));
    }

    [Fact]
    public void WebUrl_DefaultsToDefaultBaseUrlWithoutApi()
    {
        var nafru = new NafruConnect(new NafruConnectOptions { ClientId = "a", ClientSecret = "b" });
        var url = nafru.AuthorizeUrl(new AuthorizeUrlInput { RedirectUri = "r", State = "s", Scopes = ["emails.send"] }).Url;
        Assert.StartsWith("https://email.nafru.com/connect?", url);
    }

    [Fact]
    public void WebUrl_DefaultsToBaseUrlWithoutApi()
    {
        var nafru = new NafruConnect(new NafruConnectOptions { ClientId = "a", ClientSecret = "b", BaseUrl = "https://email.nafru.com/api/" });
        var url = nafru.AuthorizeUrl(new AuthorizeUrlInput { RedirectUri = "r", State = "s", Scopes = ["emails.send"] }).Url;
        Assert.StartsWith("https://email.nafru.com/connect?", url);
    }

    [Fact]
    public async Task Exchange_SendsCredentialsInBody_NoAuthorizationHeader()
    {
        var (nafru, handler) = Server(_ => Task.FromResult(Token(1)));
        var grant = await nafru.ExchangeAsync(new ExchangeInput { Code = "nfc_1", CodeVerifier = new string('v', 43), RedirectUri = "https://scout.test/cb" });
        Assert.Equal(("conn_1", "nfr_1"), (grant.ConnectionId, grant.RefreshToken));
        Assert.Equal(["emails.send"], grant.Scopes);
        var call = handler.Calls[0];
        Assert.Equal("https://api.test/oauth/token", call.Url);
        Assert.Null(call.Header("Authorization"));
        Assert.Equal("authorization_code", call.Json.GetProperty("grant_type").GetString());
        Assert.Equal("nfs_secret", call.Json.GetProperty("client_secret").GetString());
        Assert.Equal("nfc_1", call.Json.GetProperty("code").GetString());
    }

    [Fact]
    public async Task Exchange_ErrorThrows()
    {
        var (nafru, _) = Server(_ => Task.FromResult(GrantError()));
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.ExchangeAsync(new ExchangeInput { Code = "c", CodeVerifier = "v", RedirectUri = "r" }));
        Assert.Equal((400, "invalid_grant"), (error.StatusCode!.Value, error.Name));
    }

    [Fact]
    public async Task Revoke_SendsRefreshToken()
    {
        var (nafru, handler) = Server(_ => Task.FromResult(Fake.Json(new { })));
        await nafru.RevokeAsync("nfr_1");
        Assert.Equal("""{"client_id":"app_x","client_secret":"nfs_secret","token":"nfr_1"}""", handler.Calls[0].Body);
    }

    private static (NafruConnection Connection, MockHandler Handler, List<string> Saved) Open(Func<Call, Task<HttpResponseMessage>> route)
    {
        var (nafru, handler) = Server(route);
        var saved = new List<string>();
        var connection = nafru.Connection("conn_1", new ConnectionOptions
        {
            RefreshToken = "nfr_0",
            OnTokenRefresh = tokens =>
            {
                lock (saved) saved.Add(tokens.RefreshToken);
                return Task.CompletedTask;
            }
        });
        return (connection, handler, saved);
    }

    [Fact]
    public async Task FirstCall_Refreshes_Persists_UsesAccessToken()
    {
        var (connection, handler, saved) = Open(call => Task.FromResult(IsToken(call) ? Token(1) : Fake.Json(new { @object = "connection", id = "conn_1", ready = true })));
        var status = await connection.StatusAsync();
        Assert.True(status.Ready);
        Assert.Equal(["nfr_1"], saved);
        Assert.Equal("refresh_token", handler.Calls[0].Json.GetProperty("grant_type").GetString());
        Assert.Equal("nfr_0", handler.Calls[0].Json.GetProperty("refresh_token").GetString());
        var api = Api(handler).First();
        Assert.Equal(("https://api.test/connection", "Bearer nfa_1"), (api.Url, api.Header("Authorization")));
    }

    [Fact]
    public async Task ConcurrentCalls_ShareSingleRefresh()
    {
        var (connection, handler, saved) = Open(async call =>
        {
            if (!IsToken(call)) return Fake.Json(new { ready = true });
            await Task.Delay(50);
            return Token(1);
        });
        await Task.WhenAll(Enumerable.Range(0, 5).Select(_ => connection.StatusAsync()));
        Assert.Single(handler.Calls, IsToken);
        Assert.Equal(["nfr_1"], saved);
        await connection.StatusAsync();
        Assert.Single(handler.Calls, IsToken);
    }

    [Fact]
    public async Task InvalidToken_RefreshesOnceAndRetries_RotatingRefreshToken()
    {
        var refreshes = 0;
        var (connection, handler, saved) = Open(call => Task.FromResult(
            IsToken(call) ? Token(++refreshes)
            : call.Header("Authorization") == "Bearer nfa_1"
                ? Fake.Json(new { statusCode = 401, name = "invalid_token", message = "expired" }, HttpStatusCode.Unauthorized)
                : Fake.Json(new { ready = true })));
        Assert.True((await connection.StatusAsync()).Ready);
        Assert.Equal(2, refreshes);
        Assert.Equal(["Bearer nfa_1", "Bearer nfa_2"], Api(handler).Select(call => call.Header("Authorization")));
        Assert.Equal("nfr_1", handler.Calls.Where(IsToken).Last().Json.GetProperty("refresh_token").GetString());
        Assert.Equal(["nfr_1", "nfr_2"], saved);
    }

    [Fact]
    public async Task RejectedRefresh_IsConnectionRevoked()
    {
        var (connection, handler, _) = Open(_ => Task.FromResult(GrantError()));
        var error = await Assert.ThrowsAsync<NafruException>(() => connection.StatusAsync());
        Assert.Equal("connection_revoked", error.Name);
        Assert.Empty(Api(handler));
    }

    [Fact]
    public async Task PersistFailure_IsTokenPersistFailed_RetriedOnNextCall_WithoutNewRefresh()
    {
        var (nafru, handler) = Server(call => Task.FromResult(IsToken(call) ? Token(1) : Fake.Json(new { ready = true })));
        var saved = new List<string>();
        var failures = 1;
        var connection = nafru.Connection("conn_1", new ConnectionOptions
        {
            RefreshToken = "nfr_0",
            OnTokenRefresh = tokens =>
            {
                if (failures-- > 0) throw new IOException("disk dolu");
                saved.Add(tokens.RefreshToken);
                return Task.CompletedTask;
            }
        });
        var error = await Assert.ThrowsAsync<NafruException>(() => connection.StatusAsync());
        Assert.Equal("token_persist_failed", error.Name);
        Assert.Contains("disk dolu", error.Message);
        Assert.True((await connection.StatusAsync()).Ready);
        Assert.Equal(["nfr_1"], saved);
        Assert.Single(handler.Calls, IsToken);
    }

    [Fact]
    public async Task Endpoints_SendersTemplatesEmails()
    {
        var (connection, handler, _) = Open(call => Task.FromResult(IsToken(call) ? Token(1) : Fake.Json(new { id = "e1", data = Array.Empty<object>() })));
        await connection.Senders.ListAsync();
        await connection.Templates.ListAsync();
        await connection.Emails.SendAsync(new SendEmailInput { From = "a@b.co", To = ["c@d.co"], Subject = "s", Html = "<p>x</p>" }, "k1");
        await connection.Emails.GetAsync("e1");
        await connection.Emails.ListAsync();
        Assert.Equal(["GET /senders", "GET /templates", "POST /emails", "GET /emails/e1", "GET /emails"],
            Api(handler).Select(call => $"{call.Method} {new Uri(call.Url).AbsolutePath}"));
        Assert.Equal("k1", Api(handler).ElementAt(2).Header("Idempotency-Key"));
    }

    [Fact]
    public async Task ServerError_Throws()
    {
        var (connection, _, _) = Open(call => Task.FromResult(IsToken(call)
            ? Token(1)
            : Fake.Json(new { statusCode = 403, name = "insufficient_scope", message = "scope" }, HttpStatusCode.Forbidden)));
        var error = await Assert.ThrowsAsync<NafruException>(() => connection.Templates.ListAsync());
        Assert.Equal((403, "insufficient_scope"), (error.StatusCode!.Value, error.Name));
    }
}
