namespace Nafru.Email;

public record Segment : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    /// <summary><c>static</c> ya da <c>dynamic</c>.</summary>
    public string Type { get; init; } = "";
    public JsonElement? Filter { get; init; }
}

public sealed record SegmentDetail : Segment
{
    public string Object { get; init; } = "segment";
}

public sealed record CreateSegmentInput
{
    public string Name { get; init; } = "";
    /// <summary>Verilirse dinamik segment (JSON'a dizilebilen herhangi bir nesne).</summary>
    public object? Filter { get; init; }
}

public sealed record SegmentRef
{
    public string Object { get; init; } = "segment";
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
}

public record Topic : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string? Description { get; init; }
    /// <summary><c>opt_in</c> ya da <c>opt_out</c>.</summary>
    public string DefaultSubscription { get; init; } = "";
    /// <summary><c>public</c> ya da <c>private</c>.</summary>
    public string Visibility { get; init; } = "";
    public bool DoubleOptIn { get; init; }
    public string CreatedAt { get; init; } = "";
}

public sealed record TopicDetail : Topic
{
    public string Object { get; init; } = "topic";
}

public sealed record CreateTopicInput
{
    public string Name { get; init; } = "";
    public string DefaultSubscription { get; init; } = "";
    public string? Description { get; init; }
    public string? Visibility { get; init; }
    public bool? DoubleOptIn { get; init; }
}

public sealed record UpdateTopicInput
{
    public string? Name { get; init; }
    public Optional<string?> Description { get; init; }
    public string? Visibility { get; init; }
    public bool? DoubleOptIn { get; init; }
}

public sealed record TopicRef
{
    public string Object { get; init; } = "topic";
    public string Id { get; init; } = "";
}

public sealed record ContactTopic : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string? Description { get; init; }
    public string Subscription { get; init; } = "";
    /// <summary><c>pending</c>: çift onay bekliyor (<c>Subscription</c> bu durumda <c>opt_out</c> görünür).</summary>
    public string Status { get; init; } = "";
}

public sealed record UpdateContactTopicsInput
{
    public IReadOnlyList<ContactTopicSubscription> Topics { get; init; } = [];
}

public record BroadcastListItem : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string SegmentId { get; init; } = "";
    public string AudienceId { get; init; } = "";
    public string Subject { get; init; } = "";
    /// <summary><c>draft</c>, <c>scheduled</c>, <c>sending</c>, <c>sent</c>, <c>paused</c>, <c>canceled</c>, <c>failed</c>.</summary>
    public string Status { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    public string? ScheduledAt { get; init; }
    public string? SentAt { get; init; }
    /// <summary>Tekrar kuralı (şablon kaydında); yoksa <c>null</c>.</summary>
    public BroadcastRecurrence? Recurrence { get; init; }
    /// <summary>Şablonun tetik durumu: <c>active</c>, <c>paused</c>; <c>null</c> = başlatılmadı.</summary>
    public string? TriggerState { get; init; }
    /// <summary>Sonraki zamanlı çalışma (ISO 8601); yoksa <c>null</c>.</summary>
    public string? NextRunAt { get; init; }
    /// <summary>Çalışma örneğinde şablonun kimliği; yoksa <c>null</c>.</summary>
    public string? ParentId { get; init; }
}

public sealed record Broadcast : BroadcastListItem
{
    public string Object { get; init; } = "broadcast";
    public string From { get; init; } = "";
    public IReadOnlyList<string>? ReplyTo { get; init; }
    public string? PreviewText { get; init; }
    public string? TopicId { get; init; }
    public string? TemplateId { get; init; }
    public string? Html { get; init; }
    public string? Text { get; init; }
    public bool OpenTracking { get; init; }
    public bool ClickTracking { get; init; }
    public string? FinishedAt { get; init; }
    public string? FailureReason { get; init; }
    /// <summary>Şablondaki <c>{{{data.*}}}</c> bağlamı (gönderilmiş örnekte gönderim anında çözülen değer).</summary>
    public JsonElement? Data { get; init; }
    public BroadcastDataSource? DataSource { get; init; }
}

public sealed record CreateBroadcastInput
{
    /// <summary>Boşsa konu satırı.</summary>
    public string? Name { get; init; }
    public string SegmentId { get; init; } = "";
    public string? TopicId { get; init; }
    public string From { get; init; } = "";
    public string? Subject { get; init; }
    public IReadOnlyList<string>? ReplyTo { get; init; }
    public string? Html { get; init; }
    public string? Text { get; init; }
    /// <summary>Şablon kimliği ya da takma adı; <c>Html</c>/<c>Text</c> ile birlikte verilmez.</summary>
    public string? TemplateId { get; init; }
    public string? PreviewText { get; init; }
    /// <summary><c>true</c>: aynı istekte gönderir. <c>ScheduledAt</c> yalnız bununla anlamlıdır.</summary>
    public bool? Send { get; init; }
    public string? ScheduledAt { get; init; }
    public bool? OpenTracking { get; init; }
    public bool? ClickTracking { get; init; }
    /// <summary><c>{{{data.*}}}</c> değişkenlerinin değeri (JSON nesne, ≤ 256 KB).</summary>
    public object? Data { get; init; }
    public BroadcastDataSourceInput? DataSource { get; init; }
    /// <summary>Verilirse kayıt tekrarlayan bir şablondur: <c>send</c> onu başlatmaz, etkinleştirir; her çalışma yeni bir toplu gönderim oluşturur.</summary>
    public BroadcastRecurrence? Recurrence { get; init; }
}

public sealed record UpdateBroadcastInput
{
    public string? Name { get; init; }
    public string? SegmentId { get; init; }
    public Optional<string?> TopicId { get; init; }
    public string? From { get; init; }
    public string? Subject { get; init; }
    public IReadOnlyList<string>? ReplyTo { get; init; }
    public string? Html { get; init; }
    public string? Text { get; init; }
    public Optional<string?> PreviewText { get; init; }
    public bool? OpenTracking { get; init; }
    public bool? ClickTracking { get; init; }
    public Optional<object?> Data { get; init; }
    public Optional<BroadcastDataSourceInput?> DataSource { get; init; }
    public Optional<BroadcastRecurrence?> Recurrence { get; init; }
}

public sealed record SendBroadcastInput
{
    public string? ScheduledAt { get; init; }
    /// <summary>Bu gönderimin <c>{{{data.*}}}</c> bağlamı (taslaktakinin yerine).</summary>
    public object? Data { get; init; }
}

/// <summary>
/// Tekrar kuralı; saat (<c>HH:MM</c>) çalışma alanının saat dilimindedir. Bilinmeyen <c>type</c> taban türe (yalnız <c>Type</c>) çözülür.
/// </summary>
public record BroadcastRecurrence
{
    public string Type { get; init; } = "";
}

/// <summary><c>Days</c>: 0 = pazar … 6 = cumartesi.</summary>
public sealed record WeeklyRecurrence : BroadcastRecurrence
{
    public WeeklyRecurrence() => Type = "weekly";
    public IReadOnlyList<int> Days { get; init; } = [];
    public string Time { get; init; } = "";
}

/// <summary><c>Day</c>: 1–31 (ay kısaysa ayın son günü).</summary>
public sealed record MonthlyRecurrence : BroadcastRecurrence
{
    public MonthlyRecurrence() => Type = "monthly";
    public int Day { get; init; }
    public string Time { get; init; } = "";
}

/// <summary><c>EveryDays</c>: 1–365 gün.</summary>
public sealed record IntervalRecurrence : BroadcastRecurrence
{
    public IntervalRecurrence() => Type = "interval";
    public int EveryDays { get; init; }
    public string Time { get; init; } = "";
}

/// <summary><c>{{{data.*}}}</c> değişkenlerinin kaynağı. <c>url</c>: gönderim anında <c>GET</c> (https, ≤ 256 KB JSON nesne, 10 sn). <c>webhook</c>: imzalı tetik ucu.</summary>
public record BroadcastDataSourceInput
{
    public string Type { get; init; } = "";
}

public sealed record ManualDataSourceInput : BroadcastDataSourceInput
{
    public ManualDataSourceInput() => Type = "manual";
}

public sealed record UrlDataSourceInput : BroadcastDataSourceInput
{
    public UrlDataSourceInput() => Type = "url";
    public string Url { get; init; } = "";
    public Optional<string?> HeaderName { get; init; }
    public Optional<string?> HeaderValue { get; init; }

    public override string ToString() => Security.Print(this, nameof(HeaderValue));
}

public sealed record WebhookDataSourceInput : BroadcastDataSourceInput
{
    public WebhookDataSourceInput() => Type = "webhook";
    public bool? RegenerateSecret { get; init; }
}

/// <summary>Veri kaynağı (yanıt). Bilinmeyen <c>type</c> taban türe (yalnız <c>Type</c>) çözülür.</summary>
public record BroadcastDataSource
{
    public string Type { get; init; } = "";
}

public sealed record ManualDataSource : BroadcastDataSource
{
    public ManualDataSource() => Type = "manual";
}

public sealed record UrlDataSource : BroadcastDataSource
{
    public UrlDataSource() => Type = "url";
    public string Url { get; init; } = "";
    public string? HeaderName { get; init; }
    public bool HasHeaderValue { get; init; }
}

public sealed record WebhookDataSource : BroadcastDataSource
{
    public WebhookDataSource() => Type = "webhook";
    public string TriggerUrl { get; init; } = "";
    public string Secret { get; init; } = "";

    public override string ToString() => Security.Print(this, nameof(Secret));
}

public sealed record BroadcastRef
{
    public string Object { get; init; } = "broadcast";
    public string Id { get; init; } = "";
}
