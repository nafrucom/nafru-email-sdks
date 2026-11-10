global using System.Text.Json;
global using System.Text.Json.Serialization;
using System.Text.Json.Serialization.Metadata;

namespace Nafru.Email;

/// <summary>
/// PATCH alanı: atanmamışsa gövdeye hiç yazılmaz (değişmez), <c>null</c> atanırsa <c>null</c> gider (alanı temizler).
/// <code>new UpdateContactInput { FirstName = null }</code>
/// </summary>
public readonly struct Optional<T> : IOptional
{
    public Optional(T value)
    {
        Value = value;
        IsSet = true;
    }

    public T Value { get; }
    public bool IsSet { get; }
    object? IOptional.BoxedValue => Value;

    public static implicit operator Optional<T>(T value) => new(value);

    public override string ToString() => IsSet ? $"{Value}" : "(atanmadı)";
}

internal interface IOptional
{
    bool IsSet { get; }
    object? BoxedValue { get; }
}

internal static class Json
{
    /// <summary>Alan adları ağda <c>snake_case</c>; <c>null</c> alanlar yazılmaz.</summary>
    public static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        // Gövde HTML'e gömülmez; Türkçe karakter ve HTML ağda olduğu gibi gider.
        Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        Converters =
        {
            new OptionalConverterFactory(),
            new TaggedUnionConverter<BroadcastRecurrence>(new()
            {
                ["weekly"] = typeof(WeeklyRecurrence), ["monthly"] = typeof(MonthlyRecurrence), ["interval"] = typeof(IntervalRecurrence)
            }),
            new TaggedUnionConverter<BroadcastDataSourceInput>(new()
            {
                ["manual"] = typeof(ManualDataSourceInput), ["url"] = typeof(UrlDataSourceInput), ["webhook"] = typeof(WebhookDataSourceInput)
            }),
            new TaggedUnionConverter<BroadcastDataSource>(new()
            {
                ["manual"] = typeof(ManualDataSource), ["url"] = typeof(UrlDataSource), ["webhook"] = typeof(WebhookDataSource)
            })
        },
        TypeInfoResolver = new DefaultJsonTypeInfoResolver { Modifiers = { SkipUnsetOptionals } }
    };

    public static string Serialize(object value) => JsonSerializer.Serialize(value, value.GetType(), Options);

    private static void SkipUnsetOptionals(JsonTypeInfo info)
    {
        foreach (var property in info.Properties)
        {
            // Taban türün alanları önce (limit, after, … sonra türe özgü alanlar): istek gövdesi ve sorgu okunur kalır.
            if (property.AttributeProvider is System.Reflection.MemberInfo { DeclaringType: { } declaring }) property.Order = Depth(declaring);
            if (property.PropertyType.IsGenericType && property.PropertyType.GetGenericTypeDefinition() == typeof(Optional<>))
                property.ShouldSerialize = (_, value) => value is IOptional { IsSet: true };
        }
    }

    private static int Depth(Type type)
    {
        var depth = 0;
        for (var current = type.BaseType; current is not null; current = current.BaseType) depth++;
        return depth;
    }

    /// <summary>
    /// <c>type</c> alanına göre alt türe çözer; alan sırası önemsizdir (jsonb anahtarları yeniden sıralar). Bilinmeyen tür taban türe düşer, çökmez.
    /// Yalnız taban türü karşılar: alt türler varsayılan yolla yazılır, kendi <c>Type</c> alanlarıyla.
    /// </summary>
    private sealed class TaggedUnionConverter<TBase>(Dictionary<string, Type> types) : JsonConverter<TBase> where TBase : class, new()
    {
        public override bool CanConvert(Type type) => type == typeof(TBase);

        public override TBase? Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
        {
            using var document = JsonDocument.ParseValue(ref reader);
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object) return null;
            var tag = root.TryGetProperty("type", out var value) && value.ValueKind == JsonValueKind.String ? value.GetString()! : "";
            return types.TryGetValue(tag, out var target)
                ? (TBase?)root.Deserialize(target, options)
                : WithType(new TBase(), tag);
        }

        // Taban türün Type alanı init-only; çalışma zamanında sıradan bir setter'dır.
        private static TBase WithType(TBase value, string tag)
        {
            typeof(TBase).GetProperty("Type")!.SetValue(value, tag);
            return value;
        }

        public override void Write(Utf8JsonWriter writer, TBase value, JsonSerializerOptions options)
        {
            if (value.GetType() != typeof(TBase))
            {
                JsonSerializer.Serialize(writer, value, value.GetType(), options);
                return;
            }
            // Bilinmeyen tür: yalnız etiketi yaz (taban türü yeniden bu dönüştürücüye düşmesin).
            writer.WriteStartObject();
            writer.WriteString("type", (string?)typeof(TBase).GetProperty("Type")!.GetValue(value) ?? "");
            writer.WriteEndObject();
        }
    }

    private sealed class OptionalConverterFactory : JsonConverterFactory
    {
        public override bool CanConvert(Type type) => type.IsGenericType && type.GetGenericTypeDefinition() == typeof(Optional<>);

        public override JsonConverter CreateConverter(Type type, JsonSerializerOptions options) =>
            (JsonConverter)Activator.CreateInstance(typeof(OptionalConverter<>).MakeGenericType(type.GetGenericArguments()[0]))!;
    }

    private sealed class OptionalConverter<T> : JsonConverter<Optional<T>>
    {
        public override bool HandleNull => true;

        public override Optional<T> Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options) =>
            new(JsonSerializer.Deserialize<T>(ref reader, options)!);

        public override void Write(Utf8JsonWriter writer, Optional<T> value, JsonSerializerOptions options) =>
            JsonSerializer.Serialize(writer, value.Value, options);
    }
}
