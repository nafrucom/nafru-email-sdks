namespace Nafru.Email;

/// <summary>Uygulamanın müşteriden isteyebileceği izinler.</summary>
public static class AppScope
{
    public const string EmailsSend = "emails.send";
    public const string EmailsRead = "emails.read";
    public const string TemplatesRead = "templates.read";
    public const string DomainsRead = "domains.read";
    public const string SendersRead = "senders.read";
    public const string ConnectionRead = "connection.read";
}

public sealed record AuthorizeUrlInput
{
    /// <summary>Kayıtlı yönlendirme adresiyle birebir aynı olmalı.</summary>
    public string RedirectUri { get; init; } = "";
    /// <summary>CSRF koruması: istekten önce üretip oturumda saklayın, dönüşte karşılaştırın. Zorunlu.</summary>
    public string State { get; init; } = "";
    public IReadOnlyList<string> Scopes { get; init; } = [];
    /// <summary>Müşterinin e-postası biliniyorsa kayıt/giriş ekranında önerilir.</summary>
    public string? LoginHint { get; init; }
}

public sealed record AuthorizeUrl
{
    public string Url { get; init; } = "";
    /// <summary>Yalnız bu bağlanma denemesi için; <c>ExchangeAsync</c> çağrısına kadar sunucunuzda (oturumda) saklayın, tarayıcıya vermeyin.</summary>
    public string CodeVerifier { get; init; } = "";

    public override string ToString() => Security.Print(this, nameof(CodeVerifier));
}

public sealed record ExchangeInput
{
    public string Code { get; init; } = "";
    public string CodeVerifier { get; init; } = "";
    public string RedirectUri { get; init; } = "";

    public override string ToString() => Security.Print(this, nameof(Code), nameof(CodeVerifier));
}

public sealed record ConnectionGrant
{
    /// <summary><c>conn_…</c>: müşteri bağlantısının kalıcı kimliği (kendi veritabanınızda müşteriyle eşleyin).</summary>
    public string ConnectionId { get; init; } = "";
    /// <summary>Şifreleyerek saklayın; tarayıcıya vermeyin. Her yenilemede değişir (<c>OnTokenRefresh</c>).</summary>
    public string RefreshToken { get; init; } = "";
    public IReadOnlyList<string> Scopes { get; init; } = [];

    public override string ToString() => Security.Print(this, nameof(RefreshToken));
}

public sealed record ConnectionTokens(string RefreshToken)
{
    public override string ToString() => Security.Print(this, nameof(RefreshToken));
}

public sealed record ConnectionOptions
{
    public string RefreshToken { get; init; } = "";
    /// <summary>Yenileme belirteci döndüğünde çağrılır; yeni değeri KALICI olarak yazmadan eskisi geçersizdir. Hata fırlatırsa çağrı <c>token_persist_failed</c> ile döner.</summary>
    public Func<ConnectionTokens, Task> OnTokenRefresh { get; init; } = _ => Task.CompletedTask;

    public override string ToString() => Security.Print(this, nameof(RefreshToken));
}

public sealed record ConnectionWorkspace
{
    public string Name { get; init; } = "";
}

public sealed record ConnectionStatus
{
    public string Object { get; init; } = "connection";
    public string Id { get; init; } = "";
    public bool Ready { get; init; }
    /// <summary>Hazır olmak için müşterinin tamamlaması gerekenler: <c>domain</c>, <c>sender</c>, <c>plan</c>.</summary>
    public IReadOnlyList<string> Missing { get; init; } = [];
    public IReadOnlyList<string> Hints { get; init; } = [];
    public IReadOnlyList<string> Scopes { get; init; } = [];
    /// <summary><c>customer_pays</c> ya da <c>app_pays</c>.</summary>
    public string BillingMode { get; init; } = "";
    public string SetupUrl { get; init; } = "";
    public ConnectionWorkspace Workspace { get; init; } = new();
}

public sealed record SenderDomain
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
}

public sealed record ConnectionSenders
{
    public IReadOnlyList<SenderDomain> Domains { get; init; } = [];
    public string? DefaultFrom { get; init; }
}

public sealed record ConnectionTemplate
{
    public string Key { get; init; } = "";
    public string Name { get; init; } = "";
    /// <summary><c>workspace</c> ya da <c>pack</c>.</summary>
    public string Source { get; init; } = "";
    public bool CustomizedFromPack { get; init; }
}
