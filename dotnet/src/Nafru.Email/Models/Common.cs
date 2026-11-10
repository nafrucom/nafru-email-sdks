namespace Nafru.Email;

/// <summary>Sayfalanabilir liste öğesi.</summary>
public interface IHasId
{
    string Id { get; }
}

/// <summary>Sunucunun <c>{ object: 'list', data, has_more }</c> liste zarfı.</summary>
public sealed record ListResponse<T>
{
    public string Object { get; init; } = "list";
    public IReadOnlyList<T> Data { get; init; } = [];
    public bool HasMore { get; init; }
}

/// <summary>İmleçli liste sorgusu: <c>After</c> ve <c>Before</c> birlikte verilemez.</summary>
public record ListQuery
{
    /// <summary>1–100, varsayılan 20.</summary>
    public int? Limit { get; init; }
    /// <summary>Bu kimlikten sonraki kayıtlar.</summary>
    public string? After { get; init; }
    /// <summary>Bu kimlikten önceki kayıtlar.</summary>
    public string? Before { get; init; }
}

public sealed record DeletedResponse
{
    public string Object { get; init; } = "";
    public string Id { get; init; } = "";
    public bool Deleted { get; init; }
}

public sealed record Tag
{
    public string Name { get; init; } = "";
    public string Value { get; init; } = "";
}

/// <summary>Yalnız kimlik taşıyan başvuru (<c>{ id }</c>).</summary>
public sealed record IdRef
{
    public string Id { get; init; } = "";
}
