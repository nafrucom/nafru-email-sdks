namespace Nafru.Email;

public record TemplateListItem : IHasId
{
    public string Id { get; init; } = "";
    public string Name { get; init; } = "";
    public string? Alias { get; init; }
    /// <summary><c>design</c> ya da <c>html</c>.</summary>
    public string Type { get; init; } = "";
    /// <summary><c>draft</c> ya da <c>published</c>.</summary>
    public string Status { get; init; } = "";
    public string? Subject { get; init; }
    public int? CurrentVersion { get; init; }
    public bool HasUnpublishedChanges { get; init; }
    public string? PublishedAt { get; init; }
    public string CreatedAt { get; init; } = "";
    public string UpdatedAt { get; init; } = "";
}

/// <summary>Şablonda kullanılan değişken: <c>{{{AD}}}</c> ya da <c>{{{AD|yedek}}}</c>.</summary>
public sealed record TemplateVariable
{
    public string Key { get; init; } = "";
    public string Type { get; init; } = "string";
    /// <summary>Şablonda yazılı ilk yedek değer; yoksa <c>null</c>.</summary>
    public string? FallbackValue { get; init; }
}

public sealed record Template : TemplateListItem
{
    public string Object { get; init; } = "template";
    public string? PreviewText { get; init; }
    public string Html { get; init; } = "";
    public string? Text { get; init; }
    public JsonElement Design { get; init; }
    public int Revision { get; init; }
    /// <summary>Konu, ön izleme metni ve gövdede kullanılan değişkenler.</summary>
    public IReadOnlyList<TemplateVariable> Variables { get; init; } = [];
    public TemplateBrand Brand { get; init; } = new();
}

public sealed record CreateTemplateInput
{
    public string Name { get; init; } = "";
    public string? Alias { get; init; }
    public string? Subject { get; init; }
    public string? PreviewText { get; init; }
    public string Html { get; init; } = "";
    public string? Text { get; init; }
    /// <summary>Markayı şablona uygula (varsayılan <c>none</c>: HTML olduğu gibi kalır).</summary>
    public TemplateBrand? Brand { get; init; }
}

public sealed record UpdateTemplateInput
{
    /// <summary>Eşzamanlı düzenleme denetimi: önceki okumadaki <c>revision</c>.</summary>
    public int? Revision { get; init; }
    public string? Name { get; init; }
    public Optional<string?> Alias { get; init; }
    public Optional<string?> Subject { get; init; }
    public Optional<string?> PreviewText { get; init; }
    public string? Html { get; init; }
    public Optional<string?> Text { get; init; }
    public TemplateBrand? Brand { get; init; }
}

public sealed record TemplateRef
{
    public string Object { get; init; } = "template";
    public string Id { get; init; } = "";
}

public sealed record TemplateSaved
{
    public string Object { get; init; } = "template";
    public string Id { get; init; } = "";
    public int Revision { get; init; }
}

public sealed record TemplatePublished
{
    public string Object { get; init; } = "template";
    public string Id { get; init; } = "";
    public int Version { get; init; }
    public string VersionId { get; init; } = "";
    public int Revision { get; init; }
}

/// <summary>Bir dilin taslağı. API anahtarıyla yalnız <c>html</c> türü şablonda; <c>locale</c> BCP 47, ana dile indirgenir.</summary>
public sealed record PutTemplateTranslationInput
{
    public string? Subject { get; init; }
    public string? PreviewText { get; init; }
    public string Html { get; init; } = "";
    public string? Text { get; init; }
}

public sealed record TemplateTranslation
{
    public string Locale { get; init; } = "";
    public string? Subject { get; init; }
    public string? PreviewText { get; init; }
    public int DesignRevision { get; init; }
    public string UpdatedAt { get; init; } = "";
}

public sealed record TemplateTranslationDeleted
{
    public string Object { get; init; } = "template_translation";
    public string Locale { get; init; } = "";
    public bool Deleted { get; init; }
}

public sealed record BrandSocialLink
{
    /// <summary><c>website</c>, <c>x</c>, <c>facebook</c>, <c>instagram</c>, <c>linkedin</c>, <c>youtube</c>, <c>github</c>, <c>tiktok</c>.</summary>
    public string Network { get; init; } = "";
    /// <summary>http(s) adresi.</summary>
    public string Url { get; init; } = "";
}

/// <summary>Çalışma alanının markası. Ayarlanmamış renk/yazı tipi/genişlik varsayılan değerle döner; <c>Configured</c> marka hiç kaydedilmediyse <c>false</c>.</summary>
public sealed record Brand
{
    public string Object { get; init; } = "brand";
    public bool Configured { get; init; }
    public string? LogoAssetId { get; init; }
    public string? LogoUrl { get; init; }
    public string? LogoDarkAssetId { get; init; }
    public string? LogoDarkUrl { get; init; }
    public int LogoWidth { get; init; }
    public string LogoAlign { get; init; } = "";
    public bool HeaderEnabled { get; init; }
    public string AccentColor { get; init; } = "";
    public string TextColor { get; init; } = "";
    public string BackdropColor { get; init; } = "";
    public string CanvasColor { get; init; } = "";
    public string LinkColor { get; init; } = "";
    public string FontFamily { get; init; } = "";
    public string ButtonStyle { get; init; } = "";
    public int ContentWidth { get; init; }
    public string? FooterText { get; init; }
    public string? LegalText { get; init; }
    public string? PostalAddress { get; init; }
    public string? WebsiteUrl { get; init; }
    public IReadOnlyList<BrandSocialLink> SocialLinks { get; init; } = [];
    public string UnsubscribeLabel { get; init; } = "";
    public string? UpdatedAt { get; init; }
}

/// <summary>
/// <c>brand.update</c> markanın TAMAMINI değiştirir: gönderilmeyen ya da <c>null</c> olan alan "ayarlanmadı" olur. Önce <c>brand.get</c> ile okuyup değiştirerek gönderin.
/// </summary>
public sealed record UpdateBrandInput
{
    public string? LogoAssetId { get; init; }
    public string? LogoDarkAssetId { get; init; }
    public int? LogoWidth { get; init; }
    public string? LogoAlign { get; init; }
    public bool? HeaderEnabled { get; init; }
    public string? AccentColor { get; init; }
    public string? TextColor { get; init; }
    public string? BackdropColor { get; init; }
    public string? CanvasColor { get; init; }
    public string? LinkColor { get; init; }
    /// <summary><c>MODERN_SANS</c>, <c>BOOK_SANS</c>, <c>ORGANIC_SANS</c>, <c>GEOMETRIC_SANS</c>, <c>HEAVY_SANS</c>, <c>ROUNDED_SANS</c>, <c>MODERN_SERIF</c>, <c>BOOK_SERIF</c>, <c>MONOSPACE</c>.</summary>
    public string? FontFamily { get; init; }
    /// <summary><c>rectangle</c>, <c>rounded</c>, <c>pill</c>.</summary>
    public string? ButtonStyle { get; init; }
    public int? ContentWidth { get; init; }
    public string? FooterText { get; init; }
    public string? LegalText { get; init; }
    public string? PostalAddress { get; init; }
    public string? WebsiteUrl { get; init; }
    public IReadOnlyList<BrandSocialLink>? SocialLinks { get; init; }
    public string? UnsubscribeLabel { get; init; }
}

/// <summary>Şablon başına markayı ezen alanlar (yalnız <c>custom</c> kipte).</summary>
public sealed record TemplateBrandOverride
{
    public string? AccentColor { get; init; }
    public string? TextColor { get; init; }
    public string? BackdropColor { get; init; }
    public string? CanvasColor { get; init; }
    public string? FontFamily { get; init; }
    public string? LinkColor { get; init; }
    public int? ContentWidth { get; init; }
    public bool? ShowHeader { get; init; }
    public bool? ShowFooter { get; init; }
}

/// <summary>
/// Şablonun marka kipi: <c>inherit</c> marka olduğu gibi, <c>custom</c> marka + <c>Override</c>, <c>none</c> hiçbir şey eklenmez.
/// Pazarlama şablonunda <c>custom</c> ile <c>ShowFooter = false</c> 422 verir: altbilgi çıkma bağlantısını taşır.
/// </summary>
public sealed record TemplateBrand
{
    public string Mode { get; init; } = "none";
    public TemplateBrandOverride? Override { get; init; }
}
