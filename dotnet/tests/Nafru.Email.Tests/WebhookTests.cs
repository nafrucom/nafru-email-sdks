using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Nafru.Email.Tests;

public class WebhookTests
{
    private static readonly JsonElement Vector = JsonDocument.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "webhook-test-vector.json"))).RootElement;
    private static string V(string name) => Vector.GetProperty(name).GetString()!;
    private static readonly DateTimeOffset Now = DateTimeOffset.FromUnixTimeSeconds(Vector.GetProperty("now_seconds").GetInt64());

    private static bool Verify(string payload, string signature, string? timestamp = null, string? secret = null) =>
        NafruWebhook.Verify(payload, V("id"), timestamp ?? V("timestamp"), signature, secret ?? V("secret"), now: Now);

    [Fact]
    public void SharedVector_Verifies_AndTamperedPayloadFails()
    {
        Assert.True(Verify(V("payload"), V("signature")));
        Assert.False(Verify(V("payload") + " ", V("signature")));
    }

    [Fact]
    public void OneOfMultipleSignaturesIsEnough()
    {
        Assert.True(Verify(V("payload"), $"v1,bozuk {V("signature")} v2,x"));
    }

    [Fact]
    public void OldTimestampAndBadSignature_ReturnFalse()
    {
        var old = (Now.ToUnixTimeSeconds() - 301).ToString();
        var key = Convert.FromBase64String(V("secret")[6..]);
        var signature = "v1," + Convert.ToBase64String(HMACSHA256.HashData(key, Encoding.UTF8.GetBytes($"{V("id")}.{old}.{V("payload")}")));
        Assert.False(Verify(V("payload"), signature, old));
        Assert.False(Verify(V("payload"), "v1,AAAA"));
        Assert.False(Verify(V("payload"), V("signature"), "abc"));
    }

    [Fact]
    public void FutureTimestamp_MissingHeaders_ManySignatures()
    {
        var future = (Now.ToUnixTimeSeconds() + 301).ToString();
        var key = Convert.FromBase64String(V("secret")[6..]);
        var signed = "v1," + Convert.ToBase64String(HMACSHA256.HashData(key, Encoding.UTF8.GetBytes($"{V("id")}.{future}.{V("payload")}")));
        Assert.False(Verify(V("payload"), signed, future));

        Assert.False(NafruWebhook.Verify(V("payload"), "", V("timestamp"), V("signature"), V("secret"), now: Now));
        Assert.False(NafruWebhook.Verify(V("payload"), V("id"), null!, V("signature"), V("secret"), now: Now));
        Assert.False(NafruWebhook.Verify(V("payload"), V("id"), V("timestamp"), null!, V("secret"), now: Now));
        Assert.False(NafruWebhook.Verify(null!, V("id"), V("timestamp"), V("signature"), V("secret"), now: Now));

        // 32'den sonraki imzalar yok sayılır.
        var padding = string.Join(' ', Enumerable.Repeat("v1,AAAA", 32));
        Assert.False(Verify(V("payload"), $"{padding} {V("signature")}"));
        Assert.True(Verify(V("payload"), $"{string.Join(' ', Enumerable.Repeat("v1,AAAA", 31))} {V("signature")}"));
    }

    [Fact]
    public void BadSecret_Throws()
    {
        Assert.Throws<ArgumentException>(() => Verify(V("payload"), V("signature"), secret: "nope"));
        Assert.Throws<ArgumentException>(() => Verify(V("payload"), V("signature"), secret: "whsec_!!!"));
    }
}
