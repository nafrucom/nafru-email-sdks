namespace Nafru.Email.Tests;

/// <summary>Her kaynak çağrısının yöntem + yol + gövde eşlemesi.</summary>
public class ResourceTests
{
    public static TheoryData<string, Func<NafruEmail, Task>, string, string, string?> Cases => new()
    {
        { "emails.batch", n => n.Emails.BatchAsync([new BatchEmailItem { From = "a@x.test", To = ["b@x.test"], Subject = "s", Text = "t" }]), "POST", "/emails/batch", """[{"from":"a@x.test","to":["b@x.test"],"subject":"s","text":"t"}]""" },
        { "emails.get", n => n.Emails.GetAsync("e 1"), "GET", "/emails/e%201", null },
        { "emails.list", n => n.Emails.ListAsync(new ListEmailsQuery { Limit = 2, Status = "sent" }), "GET", "/emails?limit=2&status=sent", null },
        { "emails.update", n => n.Emails.UpdateAsync("e1", new UpdateEmailInput { ScheduledAt = "in 1 hour" }), "PATCH", "/emails/e1", """{"scheduled_at":"in 1 hour"}""" },
        { "emails.cancel", n => n.Emails.CancelAsync("e1"), "POST", "/emails/e1/cancel", null },
        { "domains.create", n => n.Domains.CreateAsync(new CreateDomainInput { Name = "x.test" }), "POST", "/domains", """{"name":"x.test"}""" },
        { "domains.update null", n => n.Domains.UpdateAsync("d1", new UpdateDomainInput { TrackingSubdomain = null }), "PATCH", "/domains/d1", """{"tracking_subdomain":null}""" },
        { "domains.verify", n => n.Domains.VerifyAsync("d1"), "POST", "/domains/d1/verify", null },
        { "domains.remove", n => n.Domains.RemoveAsync("d1"), "DELETE", "/domains/d1", null },
        { "contacts.get e-posta", n => n.Contacts.GetAsync("a+b@x.test"), "GET", "/contacts/a%2Bb%40x.test", null },
        { "contacts.update", n => n.Contacts.UpdateAsync("c1", new UpdateContactInput { Unsubscribed = true }), "PATCH", "/contacts/c1", """{"unsubscribed":true}""" },
        { "contacts.update temizle", n => n.Contacts.UpdateAsync("c1", new UpdateContactInput { FirstName = null, LastName = "Ak" }), "PATCH", "/contacts/c1", """{"first_name":null,"last_name":"Ak"}""" },
        { "contacts.segments.add", n => n.Contacts.Segments.AddAsync("c1", "s1"), "POST", "/contacts/c1/segments/s1", null },
        { "contacts.segments.remove", n => n.Contacts.Segments.RemoveAsync("c1", "s1"), "DELETE", "/contacts/c1/segments/s1", null },
        { "contacts.topics.list", n => n.Contacts.Topics.ListAsync("c1"), "GET", "/contacts/c1/topics", null },
        { "contacts.topics.update çıplak dizi", n => n.Contacts.Topics.UpdateAsync("c1", new UpdateContactTopicsInput { Topics = [new ContactTopicSubscription { Id = "t1", Subscription = "opt_in" }] }), "PATCH", "/contacts/c1/topics", """[{"id":"t1","subscription":"opt_in"}]""" },
        { "contactProperties.create", n => n.ContactProperties.CreateAsync(new CreateContactPropertyInput { Key = "plan", Type = "string" }), "POST", "/contact-properties", """{"key":"plan","type":"string"}""" },
        { "contactProperties.update", n => n.ContactProperties.UpdateAsync("p1", new UpdateContactPropertyInput { FallbackValue = 3 }), "PATCH", "/contact-properties/p1", """{"fallback_value":3}""" },
        { "segments.contacts", n => n.Segments.ContactsAsync("s1", new ListQuery { Limit = 3 }), "GET", "/segments/s1/contacts?limit=3", null },
        { "segments.create", n => n.Segments.CreateAsync(new CreateSegmentInput { Name = "VIP" }), "POST", "/segments", """{"name":"VIP"}""" },
        { "topics.create", n => n.Topics.CreateAsync(new CreateTopicInput { Name = "Haber", DefaultSubscription = "opt_out" }), "POST", "/topics", """{"name":"Haber","default_subscription":"opt_out"}""" },
        { "broadcasts.send", n => n.Broadcasts.SendAsync("b1", new SendBroadcastInput { ScheduledAt = "in 1 hour" }), "POST", "/broadcasts/b1/send", """{"scheduled_at":"in 1 hour"}""" },
        { "broadcasts.cancel", n => n.Broadcasts.CancelAsync("b1"), "POST", "/broadcasts/b1/cancel", null },
        { "templates.publish", n => n.Templates.PublishAsync("welcome"), "POST", "/templates/welcome/publish", null },
        { "templates.duplicate", n => n.Templates.DuplicateAsync("t1"), "POST", "/templates/t1/duplicate", null },
        { "templates.putTranslation", n => n.Templates.PutTranslationAsync("welcome", "pt-BR", new PutTemplateTranslationInput { Html = "<p>Olá</p>" }), "PUT", "/templates/welcome/translations/pt-BR", """{"html":"<p>Olá</p>"}""" },
        { "templates.removeTranslation", n => n.Templates.RemoveTranslationAsync("welcome", "de"), "DELETE", "/templates/welcome/translations/de", null },
        { "templates.create brand", n => n.Templates.CreateAsync(new CreateTemplateInput { Name = "W", Html = "x", Brand = new TemplateBrand { Mode = "custom", Override = new TemplateBrandOverride { ShowHeader = false } } }), "POST", "/templates", """{"name":"W","html":"x","brand":{"mode":"custom","override":{"show_header":false}}}""" },
        { "brand.get", n => n.Brand.GetAsync(), "GET", "/brand", null },
        { "brand.update", n => n.Brand.UpdateAsync(new UpdateBrandInput { AccentColor = "#112233", SocialLinks = [new BrandSocialLink { Network = "x", Url = "https://x.com/acme" }] }), "PUT", "/brand", """{"accent_color":"#112233","social_links":[{"network":"x","url":"https://x.com/acme"}]}""" },
        { "webhooks.create", n => n.Webhooks.CreateAsync(new CreateWebhookInput { Endpoint = "https://x.test/h", Events = ["email.sent"] }), "POST", "/webhooks", """{"endpoint":"https://x.test/h","events":["email.sent"]}""" },
        { "apiKeys.create", n => n.ApiKeys.CreateAsync(new CreateApiKeyInput { Name = "ci" }), "POST", "/api-keys", """{"name":"ci"}""" },
        { "apiKeys.remove", n => n.ApiKeys.RemoveAsync("k1"), "DELETE", "/api-keys/k1", null },
        { "events.send", n => n.Events.SendAsync(new SendEventInput { Name = "signed_up", Contact = new EventContact { Email = "a@x.test" } }), "POST", "/events", """{"name":"signed_up","contact":{"email":"a@x.test"}}""" },
        { "events.batch", n => n.Events.BatchAsync([new SendEventInput { Name = "a", Contact = new EventContact { Id = "c1" } }]), "POST", "/events/batch", """[{"name":"a","contact":{"id":"c1"}}]""" },
    };

    [Theory]
    [MemberData(nameof(Cases))]
    public async Task MapsMethodPathAndBody(string name, Func<NafruEmail, Task> run, string method, string path, string? body)
    {
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(new { id = "x" }));
        await run(nafru);
        var call = handler.Calls[0];
        Assert.True(method == call.Method.Method, name);
        Assert.Equal("https://api.test" + path, call.Url);
        Assert.Equal(body, call.Body);
    }

    [Fact]
    public async Task EventsSend_CarriesIdempotencyKey()
    {
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(new { id = "x" }));
        await nafru.Events.SendAsync(new SendEventInput { Name = "a", Contact = new EventContact { Id = "c1" } }, "abc");
        Assert.Equal("abc", handler.Calls[0].Header("Idempotency-Key"));
    }

    [Fact]
    public async Task Pagination_FollowsAfterCursor()
    {
        var pages = new[]
        {
            new { @object = "list", data = new[] { new { id = "a" }, new { id = "b" } }, has_more = true },
            new { @object = "list", data = new[] { new { id = "c" } }, has_more = false }
        };
        var index = 0;
        var (nafru, handler) = Fake.Setup(0, () => Fake.Json(pages[index++]));
        var ids = new List<string>();
        await foreach (var contact in NafruPagination.PaginateAsync(nafru.Contacts.ListAsync, new ListContactsQuery { Limit = 2 }))
            ids.Add(contact.Id);
        Assert.Equal(["a", "b", "c"], ids);
        Assert.Equal(["https://api.test/contacts?limit=2", "https://api.test/contacts?limit=2&after=b"], handler.Calls.Select(c => c.Url));
    }

    [Fact]
    public async Task Pagination_ThrowsOnError()
    {
        var (nafru, _) = Fake.Setup(0, () => Fake.Json(new { statusCode = 401, name = "unauthorized", message = "anahtar yok" }, System.Net.HttpStatusCode.Unauthorized));
        var error = await Assert.ThrowsAsync<NafruException>(async () =>
        {
            await foreach (var _ in NafruPagination.PaginateAsync(nafru.Contacts.ListAsync, new ListContactsQuery())) { }
        });
        Assert.Equal((401, "anahtar yok"), (error.StatusCode!.Value, error.Message));
    }
}
