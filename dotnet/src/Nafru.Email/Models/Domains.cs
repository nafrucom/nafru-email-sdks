namespace Nafru.Email;

public sealed record DomainRecord
{
    /// <summary><c>SPF</c>, <c>DKIM</c> ya da <c>Tracking</c>.</summary>
    public string Record { get; init; } = "";
    public string Name { get; init; } = "";
    /// <summary><c>MX</c>, <c>TXT</c> ya da <c>CNAME</c>.</summary>
    public string Type { get; init; } = "";
    public string Value { get; init; } = "";
    public string Ttl { get; init; } = "Auto";
    public string Status { get; init; } = "";
    public int? Priority { get; init; }
}

public sealed record DomainCapabilities
{
    public string Sending { get; init; } = "";
    public string Receiving { get; init; } = "";
}

public record Domain : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    /// <summary><c>not_started</c>, <c>pending</c>, <c>verified</c>, <c>failed</c>, <c>temporary_failure</c>.</summary>
    public string Status { get; init; } = "";
    public string CreatedAt { get; init; } = "";
    public string Region { get; init; } = "";
    public DomainCapabilities Capabilities { get; init; } = new();
    public bool OpenTracking { get; init; }
    public bool ClickTracking { get; init; }
    /// <summary><c>opportunistic</c> ya da <c>enforced</c>.</summary>
    public string Tls { get; init; } = "";
    public string? TrackingSubdomain { get; init; }
}

public sealed record DomainDetail : Domain
{
    public string Object { get; init; } = "domain";
    public IReadOnlyList<DomainRecord> Records { get; init; } = [];
}

public sealed record CreateDomainInput
{
    public string Name { get; init; } = "";
    public string? Region { get; init; }
    public bool? OpenTracking { get; init; }
    public bool? ClickTracking { get; init; }
    public string? Tls { get; init; }
    /// <summary>Örn. <c>track</c> → <c>track.&lt;alan-adı&gt;</c>.</summary>
    public string? TrackingSubdomain { get; init; }
}

public sealed record UpdateDomainInput
{
    public bool? OpenTracking { get; init; }
    public bool? ClickTracking { get; init; }
    public string? Tls { get; init; }
    public Optional<string?> TrackingSubdomain { get; init; }
}

public sealed record DomainRef
{
    public string Object { get; init; } = "domain";
    public string Id { get; init; } = "";
}
