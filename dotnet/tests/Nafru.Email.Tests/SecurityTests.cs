using System.Net;
using System.Text;

namespace Nafru.Email.Tests;

public class SecurityTests
{
    [Theory]
    [InlineData("http://api.example.com/api")]
    [InlineData("ftp://api.example.com")]
    [InlineData("http://localhost.example.com/api")]
    public void PlainHttp_RejectedOutsideLocalhost(string baseUrl)
    {
        var error = Assert.Throws<ArgumentException>(() => new NafruEmail("k", new NafruEmailOptions { BaseUrl = baseUrl }));
        Assert.Contains("https", error.Message);
        Assert.Throws<ArgumentException>(() => new NafruConnect(new NafruConnectOptions { ClientId = "a", ClientSecret = "b", BaseUrl = baseUrl }));
    }

    [Theory]
    [InlineData("http://localhost:48787/api")]
    [InlineData("http://app.localhost/api")]
    [InlineData("http://127.0.0.1:48787/api")]
    [InlineData("http://127.1.2.3/api")]
    [InlineData("http://[::1]:48787/api")]
    [InlineData("https://email.example.com/api")]
    public void HttpsAndLoopback_Accepted(string baseUrl)
    {
        _ = new NafruEmail("k", new NafruEmailOptions { BaseUrl = baseUrl });
        _ = new NafruConnect(new NafruConnectOptions { ClientId = "a", ClientSecret = "b", BaseUrl = baseUrl });
    }

    [Fact]
    public void WebUrl_MustBeHttps()
    {
        Assert.Throws<ArgumentException>(() => new NafruConnect(new NafruConnectOptions
        {
            ClientId = "a", ClientSecret = "b", WebUrl = "http://web.example.com"
        }));
    }

    [Theory]
    [InlineData(HttpStatusCode.Found)]
    [InlineData(HttpStatusCode.MovedPermanently)]
    [InlineData(HttpStatusCode.TemporaryRedirect)]
    public async Task Redirect_IsUnexpectedRedirect_NeverRetried(HttpStatusCode status)
    {
        var (nafru, handler) = Fake.Setup(2, () =>
        {
            var response = new HttpResponseMessage(status);
            response.Headers.Location = new Uri("https://evil.test/steal");
            return response;
        });
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.GetAsync("e1"));
        Assert.Equal(((int)status, "unexpected_redirect"), (error.StatusCode!.Value, error.Name));
        Assert.Single(handler.Calls);
    }

    [Theory]
    [InlineData("")]
    [InlineData(".")]
    [InlineData("..")]
    public async Task UnsafePathSegment_RejectedBeforeRequest(string id)
    {
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(new { id = "x" }));
        await Assert.ThrowsAsync<ArgumentException>(() => nafru.Emails.GetAsync(id));
        await Assert.ThrowsAsync<ArgumentException>(() => nafru.Contacts.Segments.AddAsync("c1", id));
        await Assert.ThrowsAsync<ArgumentException>(() => nafru.Templates.PutTranslationAsync("welcome", id, new PutTemplateTranslationInput { Html = "x" }));
        Assert.Empty(handler.Calls);
    }

    [Theory]
    [InlineData("")]
    [InlineData("k\r\nX-Evil: 1")]
    [InlineData("k\n")]
    [InlineData("k\u0000")]
    public async Task IdempotencyKey_WithControlCharsRejected(string key)
    {
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(new { id = "x" }));
        await Assert.ThrowsAsync<ArgumentException>(() => nafru.Emails.SendAsync(new SendEmailInput { To = ["x"], Text = "t" }, key));
        Assert.Empty(handler.Calls);
    }

    [Fact]
    public async Task OversizedResponse_IsResponseTooLarge()
    {
        var big = new string('a', NafruHttp.MaxResponseBytes + 1);
        var (nafru, _) = Fake.Setup(0, () => new HttpResponseMessage { Content = new StringContent(big, Encoding.UTF8, "application/json") });
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.GetAsync("e1"));
        Assert.Equal("response_too_large", error.Name);

        // Content-Length bilinmeyen akış da sınırlanır.
        var (streamed, _) = Fake.Setup(0, () => new HttpResponseMessage { Content = new StreamContent(new UnknownLengthStream(NafruHttp.MaxResponseBytes + 1)) });
        Assert.Equal("response_too_large", (await Assert.ThrowsAsync<NafruException>(() => streamed.Emails.GetAsync("e1"))).Name);
    }

    [Fact]
    public void Secrets_AreRedactedInStringForms()
    {
        const string key = "nafru_supersecretkey";
        var nafru = new NafruEmail(key);
        var connect = new NafruConnect(new NafruConnectOptions { ClientId = "app_x", ClientSecret = "nfs_supersecret" });
        object[] values =
        [
            nafru,
            connect,
            new NafruConnectOptions { ClientId = "app_x", ClientSecret = "nfs_supersecret" },
            new ConnectionGrant { ConnectionId = "conn_1", RefreshToken = "nfr_supersecret", Scopes = ["emails.send"] },
            new ConnectionTokens("nfr_supersecret"),
            new ConnectionOptions { RefreshToken = "nfr_supersecret" },
            new TokenPayload { AccessToken = "nfa_supersecret", RefreshToken = "nfr_supersecret" },
            new AuthorizeUrl { Url = "https://x", CodeVerifier = "verifier_supersecret" },
            new ExchangeInput { Code = "code_supersecret", CodeVerifier = "verifier_supersecret" },
            new CreatedApiKey { Id = "k1", Token = "nafru_supersecret" },
            new CreatedWebhook { Id = "w1", SigningSecret = "whsec_supersecret" },
            new WebhookDetail { Id = "w1", SigningSecret = "whsec_supersecret" },
            new WebhookDataSource { TriggerUrl = "https://x", Secret = "supersecret" },
            new UrlDataSourceInput { Url = "https://x", HeaderValue = "supersecret" }
        ];
        foreach (var value in values)
        {
            var text = $"{value}";
            Assert.DoesNotContain("supersecret", text);
            Assert.DoesNotContain(key, text);
        }
        Assert.Contains("conn_1", values[3].ToString());
        Assert.Contains("[REDACTED]", values[3].ToString());
    }

    [Fact]
    public async Task Errors_NeverCarryTheKey()
    {
        const string key = "nafru_supersecretkey";
        var handler = new MockHandler(_ => throw new HttpRequestException("bağlantı reddedildi"));
        var nafru = new NafruEmail(key, new NafruEmailOptions { BaseUrl = "https://api.test", HttpClient = new HttpClient(handler), MaxRetries = 0 });
        var error = await Assert.ThrowsAsync<NafruException>(() => nafru.Emails.GetAsync("e1"));
        Assert.DoesNotContain(key, error.ToString());
    }

    private sealed class UnknownLengthStream(long length) : Stream
    {
        private long _left = length;
        public override bool CanRead => true;
        public override bool CanSeek => false;
        public override bool CanWrite => false;
        public override long Length => throw new NotSupportedException();
        public override long Position { get => 0; set => throw new NotSupportedException(); }
        public override void Flush() { }
        public override long Seek(long offset, SeekOrigin origin) => throw new NotSupportedException();
        public override void SetLength(long value) => throw new NotSupportedException();
        public override void Write(byte[] buffer, int offset, int count) => throw new NotSupportedException();

        public override int Read(byte[] buffer, int offset, int count)
        {
            var n = (int)Math.Min(count, _left);
            Array.Fill(buffer, (byte)'a', offset, n);
            _left -= n;
            return n;
        }
    }
}
