using System.Reflection;
using System.Text;

namespace Nafru.Email;

internal static class Security
{
    public const string Redacted = "[REDACTED]";

    /// <summary>
    /// Yalnız https; http yalnız yerel geliştirme adreslerinde (localhost, *.localhost, 127.0.0.0/8, [::1]).
    /// Düz http'de API anahtarı ve belirteçler ağda açık gider.
    /// </summary>
    public static string RequireHttps(string url, string name)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
            throw new ArgumentException($"Nafru SDK: {name} geçerli bir mutlak adres olmalı", name);
        var local = uri.IsLoopback || uri.Host.EndsWith(".localhost", StringComparison.OrdinalIgnoreCase);
        if (uri.Scheme != Uri.UriSchemeHttps && !(uri.Scheme == Uri.UriSchemeHttp && local))
            throw new ArgumentException($"Nafru SDK: {name} must use https (http is allowed only for localhost)", name);
        return url;
    }

    /// <summary>Yol parçası: kaçırılır; boş, <c>.</c> ve <c>..</c> reddedilir (URL normalleştirmesi başka uca götürürdü).</summary>
    public static string Segment(string value)
    {
        if (string.IsNullOrEmpty(value) || value is "." or "..")
            throw new ArgumentException($"Nafru SDK: geçersiz yol parçası \"{value}\" (boş, \".\" ya da \"..\" olamaz)", nameof(value));
        return Uri.EscapeDataString(value);
    }

    /// <summary><c>Idempotency-Key</c>: boş ya da denetim karakteri (CR/LF dahil) taşıyan değer başlık enjeksiyonu olurdu.</summary>
    public static void RequireHeaderValue(string? value, string name)
    {
        if (value is not null && (value.Length == 0 || value.Any(char.IsControl)))
            throw new ArgumentException($"Nafru SDK: {name} boş olamaz ve denetim karakteri (CR, LF, …) içeremez", name);
    }

    /// <summary>Record'un varsayılan <c>ToString</c> biçimi; gizli alanlar <c>[REDACTED]</c> yazılır (günlüğe sızmasın).</summary>
    public static string Print(object value, params string[] secrets)
    {
        var builder = new StringBuilder(value.GetType().Name).Append(" { ");
        var first = true;
        foreach (var property in value.GetType().GetProperties(BindingFlags.Public | BindingFlags.Instance))
        {
            if (property.GetIndexParameters().Length > 0) continue;
            if (!first) builder.Append(", ");
            first = false;
            builder.Append(property.Name).Append(" = ").Append(secrets.Contains(property.Name) ? Redacted : property.GetValue(value));
        }
        return builder.Append(first ? "}" : " }").ToString();
    }
}
