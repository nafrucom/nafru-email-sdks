using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace Nafru.Email;

/// <summary>
/// Svix / Standard Webhooks uyumlu imza doğrulama.
/// <code>
///   imzalanan  = "{svix-id}.{svix-timestamp}.{ham gövde}"
///   anahtar    = "whsec_" sonrası base64 çözülmüş signing_secret
///   başlık     = "v1,&lt;base64 HMAC-SHA256&gt;" (anahtar döndürmede boşlukla ayrılmış birden çok imza)
/// </code>
/// </summary>
public static class NafruWebhook
{
    private const string SecretPrefix = "whsec_";
    public const int DefaultToleranceSeconds = 300;
    /// <summary>Başlıktaki imza sayısı sınırı: aşırı uzun başlık HMAC karşılaştırmasıyla işlemci tüketemesin.</summary>
    private const int MaxSignatures = 32;

    /// <summary>İmza ve zaman damgası geçerliyse <c>true</c>. Bozuk imza ya da zaman damgası <c>false</c>; bozuk <paramref name="secret"/> <see cref="ArgumentException"/> fırlatır (yapılandırma hatası).</summary>
    /// <param name="payload">HAM istek gövdesi (okunduğu gibi metin): ayrıştırılıp yeniden dizilmiş JSON imzayı bozar.</param>
    /// <param name="id"><c>svix-id</c> başlığı.</param>
    /// <param name="timestamp"><c>svix-timestamp</c> başlığı.</param>
    /// <param name="signature"><c>svix-signature</c> başlığı.</param>
    /// <param name="secret">Webhook'un <c>signing_secret</c> değeri (<c>whsec_…</c>).</param>
    /// <param name="toleranceSeconds">Tekrar saldırısına karşı izin verilen zaman farkı (saniye).</param>
    /// <param name="now">Şimdiki zaman; testler için.</param>
    public static bool Verify(string payload, string id, string timestamp, string signature, string secret,
        int toleranceSeconds = DefaultToleranceSeconds, DateTimeOffset? now = null)
    {
        if (secret is null || !secret.StartsWith(SecretPrefix, StringComparison.Ordinal))
            throw new ArgumentException("Geçersiz imza anahtarı: whsec_ ile başlamalı", nameof(secret));
        byte[] key;
        try
        {
            key = Convert.FromBase64String(secret[SecretPrefix.Length..]);
        }
        catch (FormatException)
        {
            throw new ArgumentException("Geçersiz imza anahtarı: base64 çözülemedi", nameof(secret));
        }

        // Eksik başlık ya da gövde yapılandırma hatası değil, imzasız istektir.
        if (string.IsNullOrEmpty(id) || string.IsNullOrEmpty(timestamp) || string.IsNullOrEmpty(signature) || payload is null) return false;

        var nowSeconds = (now ?? DateTimeOffset.UtcNow).ToUnixTimeSeconds();
        if (!double.TryParse(timestamp, NumberStyles.Float, CultureInfo.InvariantCulture, out var sent)
            || double.IsNaN(sent) || Math.Abs(nowSeconds - sent) > toleranceSeconds)
            return false;

        var expected = HMACSHA256.HashData(key, Encoding.UTF8.GetBytes($"{id}.{timestamp}.{payload}"));
        foreach (var candidate in signature.Split(' ').Take(MaxSignatures))
        {
            var parts = candidate.Split(',');
            if (parts.Length < 2 || parts[0] != "v1" || parts[1].Length == 0) continue;
            byte[] mac;
            try
            {
                mac = Convert.FromBase64String(parts[1]);
            }
            catch (FormatException)
            {
                continue;
            }
            if (CryptographicOperations.FixedTimeEquals(mac, expected)) return true;
        }
        return false;
    }
}
