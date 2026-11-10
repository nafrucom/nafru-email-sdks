namespace Nafru.Email;

public record Webhook : IHasId
{
    public string Id { get; init; } = "";
    public string Endpoint { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    /// <summary><c>enabled</c> ya da <c>disabled</c>.</summary>
    public string Status { get; init; } = "";
    public IReadOnlyList<string> Events { get; init; } = [];
}

public sealed record WebhookDetail : Webhook
{
    public string Object { get; init; } = "webhook";
    public string SigningSecret { get; init; } = "";

    public override string ToString() => Security.Print(this, nameof(SigningSecret));
}

public sealed record CreateWebhookInput
{
    /// <summary>Herkese açık https adresi.</summary>
    public string Endpoint { get; init; } = "";
    /// <summary><c>email.sent</c>, <c>email.delivered</c>, <c>contact.created</c>, …</summary>
    public IReadOnlyList<string> Events { get; init; } = [];
}

public sealed record CreatedWebhook
{
    public string Object { get; init; } = "webhook";
    public string Id { get; init; } = "";
    /// <summary>Yalnız bu yanıtta ve ayrıntıda görünür; <see cref="NafruWebhook.Verify"/> bununla doğrular.</summary>
    public string SigningSecret { get; init; } = "";

    public override string ToString() => Security.Print(this, nameof(SigningSecret));
}

public sealed record UpdateWebhookInput
{
    public string? Endpoint { get; init; }
    public IReadOnlyList<string>? Events { get; init; }
    public string? Status { get; init; }
}

public sealed record WebhookRef
{
    public string Object { get; init; } = "webhook";
    public string Id { get; init; } = "";
}

/// <summary>Webhook gövdesi: <c>{ type, created_at, data }</c>.</summary>
public sealed record WebhookPayload<T>
{
    public string Type { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    public T Data { get; init; } = default!;
}

public sealed record ApiKey : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    public string? LastUsedAt { get; init; }
    /// <summary><c>full_access</c> ya da <c>sending_access</c>.</summary>
    public string Permission { get; init; } = "";
    public string? DomainId { get; init; }
    public string TokenPrefix { get; init; } = "";
}

public sealed record CreateApiKeyInput
{
    public string Name { get; init; } = "";
    /// <summary>Varsayılan <c>full_access</c>.</summary>
    public string? Permission { get; init; }
    /// <summary>Yalnız <c>sending_access</c> ile: anahtarı bu alan adına kısıtlar.</summary>
    public string? DomainId { get; init; }
}

public sealed record CreatedApiKey
{
    public string Id { get; init; } = "";
    /// <summary>Tam anahtar yalnız bir kez görünür.</summary>
    public string Token { get; init; } = "";

    public override string ToString() => Security.Print(this, nameof(Token));
}

/// <summary>Olayın kişisi: <c>Email</c> (yoksa oluşturulur) ya da <c>Id</c> (yoksa 404).</summary>
public sealed record EventContact
{
    public string? Email { get; init; }
    public string? Id { get; init; }
}

public sealed record SendEventInput
{
    /// <summary><c>^[a-z0-9_.:-]{1,64}$</c>; <c>email.</c>, <c>contact.</c>, <c>segment.</c>, <c>topic.</c>, <c>automation.</c> ön ekleri ayrılmıştır.</summary>
    public string Name { get; init; } = "";
    public EventContact Contact { get; init; } = new();
    /// <summary>Değerler metin, sayı, mantıksal ya da <c>null</c>.</summary>
    public IReadOnlyDictionary<string, object?>? Properties { get; init; }
    /// <summary>ISO 8601; verilmezse alma anı.</summary>
    public string? OccurredAt { get; init; }
    /// <summary>Yalnız kişi bu istekle oluşturuluyorsa: kişiyi abonelikten çıkmış açar.</summary>
    public bool? Unsubscribed { get; init; }
}

public sealed record EventAccepted
{
    public string Id { get; init; } = "";
}

public sealed record EventBatchResponse
{
    public IReadOnlyList<EventAccepted> Data { get; init; } = [];
}

public sealed record EventItem : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string ContactId { get; init; } = "";
    public string Email { get; init; } = "";
    public IReadOnlyDictionary<string, JsonElement> Properties { get; init; } = new Dictionary<string, JsonElement>();
    /// <summary><c>api</c> ya da <c>system</c>.</summary>
    public string Source { get; init; } = "";
    public string OccurredAt { get; init; } = "";
    public string CreatedAt { get; init; } = "";
}

public sealed record ListEventsQuery : ListQuery
{
    /// <summary>Tam eşleşme; sistem olay adlarını (<c>email.opened</c>) da kabul eder.</summary>
    public string? Name { get; init; }
    public string? ContactId { get; init; }
    /// <summary><c>ContactId</c> ile birlikte verilmez.</summary>
    public string? Email { get; init; }
}
