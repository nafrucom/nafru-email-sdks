namespace Nafru.Email.Tests;

public class DevOutboxTests
{
    [Fact]
    public async Task DoesNotSend_WritesTxtAndHtml_PrintsPath()
    {
        var dir = Directory.CreateTempSubdirectory("nafru-outbox-").FullName;
        var handler = new MockHandler(_ => throw new InvalidOperationException("istek atılmamalı"));
        var nafru = new NafruEmail("k", new NafruEmailOptions { BaseUrl = "https://api.test", HttpClient = new HttpClient(handler), DevOutbox = dir });
        var previous = Console.Out;
        var output = new StringWriter();
        Console.SetOut(output);
        try
        {
            var sent = await nafru.Emails.SendAsync(new SendEmailInput
            {
                From = "a@x.com", To = ["b@y.com", "c@y.com"], Subject = "Merhaba", Html = "<p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p>"
            });
            var batch = await nafru.Emails.BatchAsync([new BatchEmailItem { From = "a@x.com", To = ["d@y.com"], Subject = "S", Text = "düz" }]);

            Assert.StartsWith("dev_", sent.Id);
            Assert.Single(batch.Data);
            Assert.Empty(handler.Calls);
            var files = Directory.GetFiles(dir);
            Assert.Equal(2, files.Count(f => f.EndsWith(".txt")));
            Assert.Equal(2, files.Count(f => f.EndsWith(".html")));
            var txt = files.Single(f => f.Contains(sent.Id) && f.EndsWith(".txt"));
            var text = await File.ReadAllTextAsync(txt);
            Assert.Contains("To: b@y.com, c@y.com", text);
            Assert.Contains("Subject: Merhaba", text);
            Assert.Contains("Selam Ali\n& hoş geldin", text);
            Assert.Contains("<b>Ali</b>", await File.ReadAllTextAsync(files.Single(f => f.Contains(sent.Id) && f.EndsWith(".html"))));
            Assert.Contains(txt, output.ToString());
        }
        finally
        {
            Console.SetOut(previous);
            Directory.Delete(dir, true);
        }
    }

    [Fact]
    public void Default_OnlyWhenNodeEnvIsDevelopment()
    {
        var previous = Environment.GetEnvironmentVariable("NODE_ENV");
        try
        {
            Environment.SetEnvironmentVariable("NODE_ENV", "development");
            Assert.Equal(".nafru/emails", DevOutbox.Resolve(null));
            Assert.Null(DevOutbox.Resolve(""));
            Environment.SetEnvironmentVariable("NODE_ENV", "production");
            Assert.Null(DevOutbox.Resolve(null));
        }
        finally
        {
            Environment.SetEnvironmentVariable("NODE_ENV", previous);
        }
    }
}
