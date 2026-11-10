namespace Nafru.Email;

/// <summary><see cref="NafruEmail"/> için isteğe bağlı ayarlar.</summary>
public sealed record NafruEmailOptions
{
    /// <summary>API'nin kök adresi; boşsa <see cref="NafruEmail.DefaultBaseUrl"/> (yerelde <c>http://localhost:48787/api</c>).</summary>
    public string? BaseUrl { get; init; }
    /// <summary>
    /// Özel <see cref="System.Net.Http.HttpClient"/> (test, proxy). Verilmezse yönlendirme izlemeyen paylaşılan bir istemci kullanılır.
    /// Kendi istemcinizde yönlendirmeyi kapatmak sizin sorumluluğunuzdadır (<c>AllowAutoRedirect = false</c>); izlenmeyen 3xx <c>unexpected_redirect</c> olur.
    /// </summary>
    public HttpClient? HttpClient { get; init; }
    /// <summary><c>429</c> ve güvenli isteklerde sunucu/ağ hatası için yeniden deneme sayısı; varsayılan 2, <c>0</c> kapatır.</summary>
    public int MaxRetries { get; init; } = 2;
    /// <summary>İstek başına zaman aşımı; varsayılan 30 sn.</summary>
    public TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(30);
    /// <summary>
    /// Dev çıkış kutusu: verilirse <c>Emails.SendAsync</c>/<c>BatchAsync</c> gönderim yapmaz, e-postayı bu klasöre <c>.txt</c> + <c>.html</c> yazar ve yolu konsola basar.
    /// Varsayılan (<c>null</c>): <c>NODE_ENV=development</c> iken <c>.nafru/emails</c>, aksi hâlde kapalı; <c>""</c> her zaman gerçek gönderim.
    /// </summary>
    public string? DevOutbox { get; init; }
}

/// <summary>
/// API anahtarıyla Nafru Email istemcisi (Resend SDK'sıyla aynı biçim): <c>new NafruEmail("nafru_...")</c>, sonra <c>nafru.Emails.SendAsync(...)</c>.
/// Hatalar <see cref="NafruException"/> olarak fırlatılır.
/// </summary>
public sealed class NafruEmail
{
    public const string SdkVersion = "0.1.1";
    internal const string UserAgent = "nafru-email-dotnet/" + SdkVersion;
    /// <summary>Nafru Email üretim API'si; <c>BaseUrl</c> verilmezse kullanılır.</summary>
    public const string DefaultBaseUrl = "https://email.nafru.com/api";

    /// <param name="apiKey">Dashboard'dan üretilen API anahtarı; boşsa <c>NAFRU_API_KEY</c> ortam değişkeni. İstemci uygulamaya gömmeyin; <c>sending_access</c> anahtarı bile e-posta gönderebilir.</param>
    public NafruEmail(string? apiKey = null) : this(apiKey, new NafruEmailOptions())
    {
    }

    public NafruEmail(string? apiKey, NafruEmailOptions options)
    {
        if (string.IsNullOrEmpty(apiKey)) apiKey = Environment.GetEnvironmentVariable("NAFRU_API_KEY");
        if (string.IsNullOrEmpty(apiKey)) throw new ArgumentException("Nafru SDK: apiKey gerekli", nameof(apiKey));
        var baseUrl = Security.RequireHttps(string.IsNullOrEmpty(options.BaseUrl) ? DefaultBaseUrl : options.BaseUrl, "baseUrl");
        var http = new NafruHttp(baseUrl, apiKey, options.HttpClient, options.MaxRetries, options.Timeout);

        Emails = new EmailsResource(http, Email.DevOutbox.Resolve(options.DevOutbox));
        Domains = new DomainsResource(http);
        Contacts = new ContactsResource(http);
        ContactProperties = new ContactPropertiesResource(http);
        Segments = new SegmentsResource(http);
        Topics = new TopicsResource(http);
        Broadcasts = new BroadcastsResource(http);
        Templates = new TemplatesResource(http);
        Brand = new BrandResource(http);
        Webhooks = new WebhooksResource(http);
        ApiKeys = new ApiKeysResource(http);
        Events = new EventsResource(http);
    }

    public EmailsResource Emails { get; }
    public DomainsResource Domains { get; }
    public ContactsResource Contacts { get; }
    public ContactPropertiesResource ContactProperties { get; }
    public SegmentsResource Segments { get; }
    public TopicsResource Topics { get; }
    public BroadcastsResource Broadcasts { get; }
    public TemplatesResource Templates { get; }
    public BrandResource Brand { get; }
    public WebhooksResource Webhooks { get; }
    public ApiKeysResource ApiKeys { get; }
    public EventsResource Events { get; }
}
