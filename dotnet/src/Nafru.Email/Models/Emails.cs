namespace Nafru.Email;

public sealed record Attachment
{
    /// <summary>Base64 metni. <c>Path</c> ile birlikte verilmez.</summary>
    public string? Content { get; init; }
    /// <summary>Herkese açık https adresi. <c>Content</c> ile birlikte verilmez.</summary>
    public string? Path { get; init; }
    public string? Filename { get; init; }
    public string? ContentType { get; init; }
    public string? ContentId { get; init; }
}

/// <summary><c>emails.send</c> ve <c>emails.batch</c> öğelerinin ortak alanları.</summary>
public abstract record EmailFields
{
    /// <summary><c>Ad &lt;adres@alan.com&gt;</c> ya da adres. Şablonla gönderimde isteğe bağlıdır (çalışma alanı varsayılanı).</summary>
    public string? From { get; init; }
    public IReadOnlyList<string> To { get; init; } = [];
    public IReadOnlyList<string>? Cc { get; init; }
    public IReadOnlyList<string>? Bcc { get; init; }
    public IReadOnlyList<string>? ReplyTo { get; init; }
    public string? Subject { get; init; }
    public IReadOnlyDictionary<string, string>? Headers { get; init; }
    public IReadOnlyList<Tag>? Tags { get; init; }
    /// <summary>ISO 8601 ya da göreli ifade (<c>in 1 hour</c>). Geçmiş an hemen gönderir; en fazla 30 gün sonrası.</summary>
    public string? ScheduledAt { get; init; }
    public string? Html { get; init; }
    public string? Text { get; init; }
}

public sealed record SendEmailInput : EmailFields
{
    public IReadOnlyList<Attachment>? Attachments { get; init; }
    /// <summary>Şablonla gönderim: <c>Html</c>/<c>Text</c>/<c>Attachments</c> ile birlikte verilmez.</summary>
    public EmailTemplate? Template { get; init; }
}

public sealed record EmailTemplate
{
    /// <summary>Şablon kimliği ya da takma adı.</summary>
    public string Id { get; init; } = "";
    /// <summary>Değerler metin ya da sayı.</summary>
    public IReadOnlyDictionary<string, object>? Variables { get; init; }
}

/// <summary>Toplu öğe: ek ve şablon desteklenmez; <c>From</c> ve <c>Subject</c> zorunlu.</summary>
public sealed record BatchEmailItem : EmailFields;

public sealed record SendEmailResponse
{
    public string Id { get; init; } = "";
}

public sealed record BatchEmailResponse
{
    public IReadOnlyList<IdRef> Data { get; init; } = [];
}

public record EmailListItem : IHasId
{
    public string Id { get; init; } = "";
    public IReadOnlyList<string> To { get; init; } = [];
    public string From { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    public string Subject { get; init; } = "";
    public IReadOnlyList<string>? Bcc { get; init; }
    public IReadOnlyList<string>? Cc { get; init; }
    public IReadOnlyList<string>? ReplyTo { get; init; }
    /// <summary><c>queued</c>, <c>scheduled</c>, <c>sent</c>, <c>delivered</c>, <c>delivery_delayed</c>, <c>bounced</c>, <c>complained</c>, <c>failed</c>, <c>canceled</c>, …</summary>
    public string LastEvent { get; init; } = "";
    public string? ScheduledAt { get; init; }
    public string? MessageId { get; init; }
}

public sealed record EmailEvent
{
    public string Id { get; init; } = "";
    public string Type { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    public JsonElement Detail { get; init; }
}

public sealed record EmailDetail : EmailListItem
{
    public string Object { get; init; } = "email";
    public string? Html { get; init; }
    public string? Text { get; init; }
    public IReadOnlyList<Tag> Tags { get; init; } = [];
    public IReadOnlyList<EmailEvent> Events { get; init; } = [];
}

public sealed record ListEmailsQuery : ListQuery
{
    public string? Status { get; init; }
}

public sealed record UpdateEmailInput
{
    public string ScheduledAt { get; init; } = "";
}

public sealed record EmailRef
{
    public string Object { get; init; } = "email";
    public string Id { get; init; } = "";
}
