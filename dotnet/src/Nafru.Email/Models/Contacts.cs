namespace Nafru.Email;

public record Contact : IHasId
{
    public string Id { get; init; } = "";
    public string Email { get; init; } = "";
    public string? FirstName { get; init; }
    public string? LastName { get; init; }
    public bool Unsubscribed { get; init; }
    /// <summary>ISO 639-1 ana dil kodu; bölgeli kod (<c>pt-BR</c>) sunucuda ana dile indirgenir.</summary>
    public string? Locale { get; init; }
    public string CreatedAt { get; init; } = "";
}

/// <summary>Kişi alanının değeri: <c>Type</c> <c>string</c> ya da <c>number</c>.</summary>
public sealed record ContactPropertyValue
{
    public string Type { get; init; } = "";
    public JsonElement Value { get; init; }
}

public sealed record ContactDetail : Contact
{
    public string Object { get; init; } = "contact";
    /// <summary>Yalnız değeri olan alanlar.</summary>
    public IReadOnlyDictionary<string, ContactPropertyValue> Properties { get; init; } = new Dictionary<string, ContactPropertyValue>();
}

public sealed record ContactTopicSubscription
{
    public string Id { get; init; } = "";
    /// <summary><c>opt_in</c> ya da <c>opt_out</c>.</summary>
    public string Subscription { get; init; } = "";
}

public sealed record CreateContactInput
{
    public string Email { get; init; } = "";
    public string? FirstName { get; init; }
    public string? LastName { get; init; }
    public bool? Unsubscribed { get; init; }
    public string? Locale { get; init; }
    /// <summary>Değerler metin, sayı ya da <c>null</c>.</summary>
    public IReadOnlyDictionary<string, object?>? Properties { get; init; }
    public IReadOnlyList<IdRef>? Segments { get; init; }
    public IReadOnlyList<ContactTopicSubscription>? Topics { get; init; }
}

public sealed record UpdateContactInput
{
    public Optional<string?> FirstName { get; init; }
    public Optional<string?> LastName { get; init; }
    public bool? Unsubscribed { get; init; }
    public Optional<string?> Locale { get; init; }
    public IReadOnlyDictionary<string, object?>? Properties { get; init; }
}

public sealed record ListContactsQuery : ListQuery
{
    /// <summary>E-posta, ad ya da soyad içinde arar.</summary>
    public string? Search { get; init; }
}

public sealed record ContactRef
{
    public string Object { get; init; } = "contact";
    public string Id { get; init; } = "";
}

public sealed record DeletedContact
{
    public string Object { get; init; } = "contact";
    public string Contact { get; init; } = "";
    public bool Deleted { get; init; }
}

/// <summary><c>contacts.segments.add/remove</c> yanıtı.</summary>
public sealed record ContactSegmentChange
{
    public string Id { get; init; } = "";
    public bool? Deleted { get; init; }
}

public record ContactProperty : IHasId
{
    public string Id { get; init; } = "";
    public string Key { get; init; } = "";
    /// <summary><c>string</c> ya da <c>number</c>.</summary>
    public string Type { get; init; } = "";
    public JsonElement? FallbackValue { get; init; }
    public string CreatedAt { get; init; } = "";
}

public sealed record ContactPropertyDetail : ContactProperty
{
    public string Object { get; init; } = "contact_property";
}

public sealed record CreateContactPropertyInput
{
    public string Key { get; init; } = "";
    public string Type { get; init; } = "";
    /// <summary>Metin ya da sayı.</summary>
    public object? FallbackValue { get; init; }
}

public sealed record UpdateContactPropertyInput
{
    public Optional<object?> FallbackValue { get; init; }
}

public sealed record ContactPropertyRef
{
    public string Object { get; init; } = "contact_property";
    public string Id { get; init; } = "";
}
