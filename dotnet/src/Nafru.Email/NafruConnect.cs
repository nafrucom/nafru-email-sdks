using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;

namespace Nafru.Email;

public sealed record NafruConnectOptions
{
    /// <summary>Kayıtlı uygulamanın <c>app_…</c> kimliği (değişmez).</summary>
    public string ClientId { get; init; } = "";
    /// <summary>Yalnız sunucunuzda; istemci uygulamaya girmez.</summary>
    public string ClientSecret { get; init; } = "";
    /// <summary>API'nin kök adresi; boşsa <see cref="NafruEmail.DefaultBaseUrl"/>.</summary>
    public string? BaseUrl { get; init; }
    /// <summary>İzin ekranının (Nafru web uygulaması) kök adresi; verilmezse <c>BaseUrl</c> sonundaki <c>/api</c> atılarak.</summary>
    public string? WebUrl { get; init; }
    /// <summary>Bkz. <see cref="NafruEmailOptions.HttpClient"/>: kendi istemcinizde yönlendirmeyi kapatmak sizin sorumluluğunuzdadır.</summary>
    public HttpClient? HttpClient { get; init; }
    public int MaxRetries { get; init; } = 2;
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(30);
    /// <summary>
    /// Dev çıkış kutusu: verilirse <c>Connection(...).Emails.SendAsync</c> gönderim yapmaz, e-postayı bu klasöre yazar.
    /// Varsayılan (<c>null</c>): <c>NODE_ENV=development</c> iken <c>.nafru/emails</c>; <c>""</c> her zaman gerçek gönderim.
    /// </summary>
    public string? DevOutbox { get; init; }

    public override string ToString() => Security.Print(this, nameof(ClientSecret));
}

/// <summary>
/// "Nafru ile bağlan": müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına gönderir. API anahtarı kopyalama yoktur.
/// Tek alan adı/anahtar için <see cref="NafruEmail"/> kullanın.
/// </summary>
public sealed class NafruConnect
{
    private readonly NafruHttp _oauth;
    private readonly string _clientId;
    private readonly string _clientSecret;
    private readonly string _web;
    private readonly string? _devOutbox;

    public NafruConnect(NafruConnectOptions options)
    {
        if (string.IsNullOrEmpty(options.ClientId)) throw new ArgumentException("Nafru SDK: clientId gerekli", nameof(options));
        if (string.IsNullOrEmpty(options.ClientSecret)) throw new ArgumentException("Nafru SDK: clientSecret gerekli", nameof(options));
        _clientId = options.ClientId;
        _clientSecret = options.ClientSecret;
        var baseUrl = Security.RequireHttps(string.IsNullOrEmpty(options.BaseUrl) ? NafruEmail.DefaultBaseUrl : options.BaseUrl, "baseUrl");
        // Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
        _oauth = new NafruHttp(baseUrl, null, options.HttpClient, options.MaxRetries, options.Timeout);
        _devOutbox = DevOutbox.Resolve(options.DevOutbox);
        _web = Security.RequireHttps(options.WebUrl ?? Regex.Replace(baseUrl, "/api/*$", ""), "webUrl").TrimEnd('/');
    }

    /// <summary>Saklanan yenileme belirteciyle bir müşteri bağlantısı. Yenileme otomatiktir; yeni belirteç <c>OnTokenRefresh</c> ile gelir.</summary>
    public NafruConnection Connection(string connectionId, ConnectionOptions options) =>
        new(connectionId, _oauth, new TokenManager(_oauth, _clientId, _clientSecret, options), _devOutbox);

    private static string Base64Url(byte[] bytes) => Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    /// <summary>PKCE (S256): 32 rastgele bayttan 43 karakterlik doğrulayıcı ve SHA-256 sınaması.</summary>
    public static (string Verifier, string Challenge) CreatePkce()
    {
        var verifier = Base64Url(RandomNumberGenerator.GetBytes(32));
        return (verifier, Base64Url(SHA256.HashData(Encoding.ASCII.GetBytes(verifier))));
    }

    /// <summary>
    /// Müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresi. <c>CodeVerifier</c>'ı oturumda saklayın; dönüşte <see cref="ExchangeAsync"/>'e verin.
    /// Dönüşte <c>state</c>'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur.
    /// </summary>
    public AuthorizeUrl AuthorizeUrl(AuthorizeUrlInput input)
    {
        if (string.IsNullOrEmpty(input.State)) throw new ArgumentException("Nafru SDK: state gerekli (CSRF koruması)", nameof(input));
        if (input.Scopes.Count == 0) throw new ArgumentException("Nafru SDK: en az bir izin (scopes) gerekli", nameof(input));
        var (verifier, challenge) = CreatePkce();
        var parameters = new List<(string, string)>
        {
            ("client_id", _clientId),
            ("redirect_uri", input.RedirectUri),
            ("state", input.State),
            ("scope", string.Join(' ', input.Scopes)),
            ("code_challenge", challenge),
            ("code_challenge_method", "S256")
        };
        if (!string.IsNullOrEmpty(input.LoginHint)) parameters.Add(("login_hint", input.LoginHint));
        var query = string.Join("&", parameters.Select(p => $"{p.Item1}={Uri.EscapeDataString(p.Item2)}"));
        return new AuthorizeUrl { Url = $"{_web}/connect?{query}", CodeVerifier = verifier };
    }

    /// <summary>Dönüşteki tek kullanımlık <c>code</c>'u bağlantıya çevirir (sunucunuzdan çağırın).</summary>
    public async Task<ConnectionGrant> ExchangeAsync(ExchangeInput input, CancellationToken cancellationToken = default)
    {
        var token = await _oauth.SendAsync<TokenPayload>(HttpMethod.Post, "/oauth/token", body: new Dictionary<string, string>
        {
            ["grant_type"] = "authorization_code",
            ["client_id"] = _clientId,
            ["client_secret"] = _clientSecret,
            ["code"] = input.Code,
            ["code_verifier"] = input.CodeVerifier,
            ["redirect_uri"] = input.RedirectUri
        }, cancellationToken: cancellationToken).ConfigureAwait(false);
        return new ConnectionGrant { ConnectionId = token.ConnectionId, RefreshToken = token.RefreshToken, Scopes = token.Scopes };
    }

    /// <summary>Bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur.</summary>
    public Task RevokeAsync(string refreshToken, CancellationToken cancellationToken = default) =>
        _oauth.SendAsync<JsonElement>(HttpMethod.Post, "/oauth/revoke", body: new Dictionary<string, string>
        {
            ["client_id"] = _clientId,
            ["client_secret"] = _clientSecret,
            ["token"] = refreshToken
        }, cancellationToken: cancellationToken);
}

internal sealed record TokenPayload
{
    public string AccessToken { get; init; } = "";
    public string RefreshToken { get; init; } = "";
    public int ExpiresIn { get; init; }
    public string ConnectionId { get; init; } = "";
    public IReadOnlyList<string> Scopes { get; init; } = [];

    public override string ToString() => Security.Print(this, nameof(AccessToken), nameof(RefreshToken));
}

/// <summary>
/// Bağlantının erişim belirtecini tutar ve yeniler. Eşzamanlı çağrılar TEK yenilemeyi paylaşır (tek uçuş): dönüşlü yenileme belirteci
/// ikinci bir eşzamanlı yenilemede "yeniden kullanım" sayılır ve bağlantıyı iptal ettirirdi.
/// </summary>
internal sealed class TokenManager
{
    /// <summary>Süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı).</summary>
    private static readonly TimeSpan EarlyRefresh = TimeSpan.FromSeconds(30);

    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly NafruHttp _oauth;
    private readonly string _clientId;
    private readonly string _clientSecret;
    private readonly Func<ConnectionTokens, Task> _onTokenRefresh;
    private string _refreshToken;
    private string? _accessToken;
    private DateTimeOffset _expiresAt;
    /// <summary>Yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı: eski belirteç artık geçersiz, bu kaybolmamalı.</summary>
    private bool _unpersisted;

    public TokenManager(NafruHttp oauth, string clientId, string clientSecret, ConnectionOptions options)
    {
        _oauth = oauth;
        _clientId = clientId;
        _clientSecret = clientSecret;
        _refreshToken = options.RefreshToken;
        _onTokenRefresh = options.OnTokenRefresh;
    }

    /// <summary>Geçerli erişim belirteci; yoksa ya da dolmak üzereyse tek uçuşla yeniler.</summary>
    public async Task<string> AccessTokenAsync(CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_unpersisted) await PersistAsync().ConfigureAwait(false);
            if (_accessToken is not null && DateTimeOffset.UtcNow < _expiresAt - EarlyRefresh) return _accessToken;
            return await RefreshAsync().ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    /// <summary>Sunucu 401 <c>invalid_token</c> dedi: eldeki belirteci at ve yenile (aynı belirteçle eşzamanlı 401'ler tek yenilemeyi paylaşır).</summary>
    public async Task<string> InvalidateAsync(string stale, CancellationToken cancellationToken)
    {
        await _gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (_accessToken == stale) _accessToken = null;
            return _accessToken ?? await RefreshAsync().ConfigureAwait(false);
        }
        finally
        {
            _gate.Release();
        }
    }

    private async Task<string> RefreshAsync()
    {
        TokenPayload token;
        try
        {
            // Çağıranın iptali kullanılmaz: sunucu belirteci döndürdükten sonra yanıtı bırakmak bağlantıyı koparır.
            token = await _oauth.SendAsync<TokenPayload>(HttpMethod.Post, "/oauth/token", body: new Dictionary<string, string>
            {
                ["grant_type"] = "refresh_token",
                ["client_id"] = _clientId,
                ["client_secret"] = _clientSecret,
                ["refresh_token"] = _refreshToken
            }, cancellationToken: CancellationToken.None).ConfigureAwait(false);
        }
        // Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi döner.
        catch (NafruException error) when (error.Name is "invalid_grant" or "connection_revoked"
                                           || (error.StatusCode == 403 && error.Name != "rate_limit_exceeded"))
        {
            throw new NafruException(error.StatusCode, "connection_revoked",
                "Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir.",
                error.Errors, error.RetryAfter, error);
        }
        _refreshToken = token.RefreshToken;
        _accessToken = token.AccessToken;
        _expiresAt = DateTimeOffset.UtcNow.AddSeconds(token.ExpiresIn);
        await PersistAsync().ConfigureAwait(false);
        return token.AccessToken;
    }

    private async Task PersistAsync()
    {
        try
        {
            await _onTokenRefresh(new ConnectionTokens(_refreshToken)).ConfigureAwait(false);
            _unpersisted = false;
        }
        catch (Exception cause)
        {
            _unpersisted = true;
            throw new NafruException(null, "token_persist_failed", $"Yeni yenileme belirteci saklanamadı: {cause.Message}", innerException: cause);
        }
    }
}

/// <summary>
/// Bir müşteri bağlantısı adına çağrı yapar. Her denemede belirteç alınır; 401 <c>invalid_token</c> (süre dolmuş / yenilenmiş) ise bir kez yenileyip tekrar dener.
/// Yönetim uçları (anahtar, domain, kişi, kampanya) bağlantı belirteciyle çağrılamaz.
/// </summary>
public sealed class NafruConnection
{
    internal NafruConnection(string id, NafruHttp oauth, TokenManager tokens, string? devOutbox)
    {
        Id = id;
        var http = new ConnectionHttp(oauth, tokens);
        _http = http;
        Senders = new ConnectionSendersResource(http);
        Templates = new ConnectionTemplatesResource(http);
        Emails = new ConnectionEmailsResource(new EmailsResource(http, devOutbox));
    }

    private readonly INafruHttp _http;

    public string Id { get; }
    public ConnectionSendersResource Senders { get; }
    public ConnectionTemplatesResource Templates { get; }
    public ConnectionEmailsResource Emails { get; }

    /// <summary><c>GET /connection</c>: hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi.</summary>
    public Task<ConnectionStatus> StatusAsync(CancellationToken cancellationToken = default) =>
        _http.SendAsync<ConnectionStatus>(HttpMethod.Get, "/connection", cancellationToken: cancellationToken);
}

public sealed class ConnectionSendersResource
{
    private readonly INafruHttp _http;
    internal ConnectionSendersResource(INafruHttp http) => _http = http;

    public Task<ConnectionSenders> ListAsync(CancellationToken cancellationToken = default) =>
        _http.SendAsync<ConnectionSenders>(HttpMethod.Get, "/senders", cancellationToken: cancellationToken);
}

public sealed class ConnectionTemplatesResource
{
    private readonly INafruHttp _http;
    internal ConnectionTemplatesResource(INafruHttp http) => _http = http;

    /// <summary>Müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe (müşterinin kendi kopyası paketi gölgeler).</summary>
    public Task<ListResponse<ConnectionTemplate>> ListAsync(CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<ConnectionTemplate>>(HttpMethod.Get, "/templates", cancellationToken: cancellationToken);
}

/// <summary>Bağlantı adına yalnız gönderim ve okuma.</summary>
public sealed class ConnectionEmailsResource
{
    private readonly EmailsResource _emails;
    internal ConnectionEmailsResource(EmailsResource emails) => _emails = emails;

    public Task<SendEmailResponse> SendAsync(SendEmailInput input, string? idempotencyKey = null, CancellationToken cancellationToken = default) =>
        _emails.SendAsync(input, idempotencyKey, cancellationToken);

    public Task<EmailDetail> GetAsync(string id, CancellationToken cancellationToken = default) => _emails.GetAsync(id, cancellationToken);

    public Task<ListResponse<EmailListItem>> ListAsync(ListEmailsQuery? query = null, CancellationToken cancellationToken = default) =>
        _emails.ListAsync(query, cancellationToken);
}

internal sealed class ConnectionHttp : INafruHttp
{
    private readonly NafruHttp _http;
    private readonly TokenManager _tokens;
    private volatile string? _current;

    public ConnectionHttp(NafruHttp oauth, TokenManager tokens)
    {
        _tokens = tokens;
        _http = oauth.WithAuthorize(async cancellationToken =>
        {
            var token = await tokens.AccessTokenAsync(cancellationToken).ConfigureAwait(false);
            _current = token;
            return token;
        });
    }

    public async Task<T> SendAsync<T>(HttpMethod method, string path, object? query = null, object? body = null,
        string? idempotencyKey = null, CancellationToken cancellationToken = default)
    {
        try
        {
            return await _http.SendAsync<T>(method, path, query, body, idempotencyKey, cancellationToken).ConfigureAwait(false);
        }
        catch (NafruException error) when (error.Name == "invalid_token" && _current is { } stale)
        {
            await _tokens.InvalidateAsync(stale, cancellationToken).ConfigureAwait(false);
            return await _http.SendAsync<T>(method, path, query, body, idempotencyKey, cancellationToken).ConfigureAwait(false);
        }
    }
}
