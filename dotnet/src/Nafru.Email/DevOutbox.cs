using System.Net;
using System.Text.RegularExpressions;

namespace Nafru.Email;

internal static class DevOutbox
{
    public const string DefaultDir = ".nafru/emails";

    /// <summary><c>DevOutbox</c> verilmezse: yalnız <c>NODE_ENV=development</c> iken <c>.nafru/emails</c>; boş dize her zaman gerçek gönderim.</summary>
    public static string? Resolve(string? configured)
    {
        if (configured is not null) return configured.Length > 0 ? configured : null;
        return Environment.GetEnvironmentVariable("NODE_ENV") == "development" ? DefaultDir : null;
    }

    private static string List(IReadOnlyList<string>? values) => values is null ? "" : string.Join(", ", values);

    // shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
    private static string HtmlToText(string html)
    {
        var text = Regex.Replace(html, @"<(style|script)[\s\S]*?</\1>", "", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, @"<br\s*/?>|</(p|div|h[1-6]|li|tr)>", "\n", RegexOptions.IgnoreCase);
        text = Regex.Replace(text, "<[^>]+>", "");
        text = text.Replace("&nbsp;", " ").Replace("&lt;", "<").Replace("&gt;", ">").Replace("&quot;", "\"").Replace("&amp;", "&");
        return Regex.Replace(text, @"\n{3,}", "\n\n").Trim();
    }

    private static string BodyText(EmailFields email)
    {
        if (!string.IsNullOrEmpty(email.Text)) return email.Text;
        if (!string.IsNullOrEmpty(email.Html)) return HtmlToText(email.Html);
        if (email is SendEmailInput { Template: { } template })
        {
            var variables = JsonSerializer.Serialize(template.Variables ?? new Dictionary<string, object>(), new JsonSerializerOptions { WriteIndented = true });
            return $"[şablon {template.Id}]\n{variables}";
        }
        return "";
    }

    /// <summary>E-postayı göndermeden <paramref name="dir"/> altına <c>.txt</c> ve <c>.html</c> olarak yazar, yolu ve düz metni konsola basar.</summary>
    public static async Task<string> WriteAsync(string dir, EmailFields email, CancellationToken cancellationToken)
    {
        var id = $"dev_{DateTimeOffset.UtcNow.ToUnixTimeMilliseconds():x}{System.Security.Cryptography.RandomNumberGenerator.GetHexString(6, lowercase: true)}";
        var folder = Path.GetFullPath(dir);
        var basePath = Path.Combine(folder, $"{DateTime.UtcNow:yyyy-MM-dd'T'HH-mm-ss-fff'Z'}-{id}");
        var headers = new List<string?>
        {
            $"From: {email.From}",
            $"To: {List(email.To)}",
            email.Cc is null ? null : $"Cc: {List(email.Cc)}",
            email.Bcc is null ? null : $"Bcc: {List(email.Bcc)}",
            email.ReplyTo is null ? null : $"Reply-To: {List(email.ReplyTo)}",
            $"Subject: {email.Subject}",
            email.ScheduledAt is null ? null : $"Scheduled-At: {email.ScheduledAt}"
        }.Where(line => line is not null);
        var body = BodyText(email);
        var text = $"{string.Join("\n", headers)}\n\n{body}\n";
        var html = email.Html ?? $"<pre>{WebUtility.HtmlEncode(body)}</pre>";

        Directory.CreateDirectory(folder);
        await File.WriteAllTextAsync($"{basePath}.txt", text, cancellationToken).ConfigureAwait(false);
        await File.WriteAllTextAsync($"{basePath}.html", html, cancellationToken).ConfigureAwait(false);
        Console.WriteLine($"[nafru] dev: e-posta gönderilmedi\n  {basePath}.txt\n  {basePath}.html\n\n{text}");
        return id;
    }
}
