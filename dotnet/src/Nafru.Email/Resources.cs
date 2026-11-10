namespace Nafru.Email;

internal static class PathSegment
{
    /// <summary>Yol parçası: kimlik ya da e-posta (kişi uçları e-postayı kimlik gibi kabul eder) güvenle kaçırılır.</summary>
    public static string Seg(string value) => Security.Segment(value);
}

public sealed class EmailsResource
{
    private readonly INafruHttp _http;
    private readonly string? _devOutbox;

    internal EmailsResource(INafruHttp http, string? devOutbox)
    {
        _http = http;
        _devOutbox = devOutbox;
    }

    /// <summary><c>POST /emails</c>. <c>ScheduledAt</c> verilirse zamanlanır; <paramref name="idempotencyKey"/> ile yineleme güvenlidir.</summary>
    public async Task<SendEmailResponse> SendAsync(SendEmailInput input, string? idempotencyKey = null, CancellationToken cancellationToken = default)
    {
        if (_devOutbox is not null) return new SendEmailResponse { Id = await DevOutbox.WriteAsync(_devOutbox, input, cancellationToken).ConfigureAwait(false) };
        return await _http.SendAsync<SendEmailResponse>(HttpMethod.Post, "/emails", body: input, idempotencyKey: idempotencyKey, cancellationToken: cancellationToken).ConfigureAwait(false);
    }

    /// <summary><c>POST /emails/batch</c>: en çok 100 e-posta; ek ve şablon desteklenmez.</summary>
    public async Task<BatchEmailResponse> BatchAsync(IReadOnlyList<BatchEmailItem> input, string? idempotencyKey = null, CancellationToken cancellationToken = default)
    {
        if (_devOutbox is null)
            return await _http.SendAsync<BatchEmailResponse>(HttpMethod.Post, "/emails/batch", body: input, idempotencyKey: idempotencyKey, cancellationToken: cancellationToken).ConfigureAwait(false);
        var data = new List<IdRef>();
        foreach (var item in input) data.Add(new IdRef { Id = await DevOutbox.WriteAsync(_devOutbox, item, cancellationToken).ConfigureAwait(false) });
        return new BatchEmailResponse { Data = data };
    }

    public Task<EmailDetail> GetAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<EmailDetail>(HttpMethod.Get, $"/emails/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<ListResponse<EmailListItem>> ListAsync(ListEmailsQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<EmailListItem>>(HttpMethod.Get, "/emails", query, cancellationToken: cancellationToken);

    /// <summary>Zamanlanmış e-postanın gönderim anını değiştirir.</summary>
    public Task<EmailRef> UpdateAsync(string id, UpdateEmailInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<EmailRef>(HttpMethod.Patch, $"/emails/{PathSegment.Seg(id)}", body: input, cancellationToken: cancellationToken);

    /// <summary>Zamanlanmış e-postayı iptal eder.</summary>
    public Task<EmailRef> CancelAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<EmailRef>(HttpMethod.Post, $"/emails/{PathSegment.Seg(id)}/cancel", cancellationToken: cancellationToken);
}

public sealed class DomainsResource
{
    private readonly INafruHttp _http;
    internal DomainsResource(INafruHttp http) => _http = http;

    public Task<DomainDetail> CreateAsync(CreateDomainInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DomainDetail>(HttpMethod.Post, "/domains", body: input, cancellationToken: cancellationToken);

    public Task<DomainDetail> GetAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DomainDetail>(HttpMethod.Get, $"/domains/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<ListResponse<Domain>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<Domain>>(HttpMethod.Get, "/domains", query, cancellationToken: cancellationToken);

    public Task<DomainRef> UpdateAsync(string id, UpdateDomainInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DomainRef>(HttpMethod.Patch, $"/domains/{PathSegment.Seg(id)}", body: input, cancellationToken: cancellationToken);

    public Task<DeletedResponse> RemoveAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/domains/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    /// <summary>DNS kayıtlarını denetletir; sonuç <see cref="GetAsync"/> ile okunur.</summary>
    public Task<DomainRef> VerifyAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DomainRef>(HttpMethod.Post, $"/domains/{PathSegment.Seg(id)}/verify", cancellationToken: cancellationToken);
}

/// <summary>Kişi uçlarında kimlik yerine e-posta adresi de verilebilir.</summary>
public sealed class ContactsResource
{
    private readonly INafruHttp _http;

    internal ContactsResource(INafruHttp http)
    {
        _http = http;
        Segments = new ContactSegmentsResource(http);
        Topics = new ContactTopicsResource(http);
    }

    public ContactSegmentsResource Segments { get; }
    public ContactTopicsResource Topics { get; }

    public Task<ContactRef> CreateAsync(CreateContactInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactRef>(HttpMethod.Post, "/contacts", body: input, cancellationToken: cancellationToken);

    public Task<ContactDetail> GetAsync(string idOrEmail, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactDetail>(HttpMethod.Get, $"/contacts/{PathSegment.Seg(idOrEmail)}", cancellationToken: cancellationToken);

    public Task<ListResponse<Contact>> ListAsync(ListContactsQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<Contact>>(HttpMethod.Get, "/contacts", query, cancellationToken: cancellationToken);

    public Task<ContactRef> UpdateAsync(string idOrEmail, UpdateContactInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactRef>(HttpMethod.Patch, $"/contacts/{PathSegment.Seg(idOrEmail)}", body: input, cancellationToken: cancellationToken);

    public Task<DeletedContact> RemoveAsync(string idOrEmail, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedContact>(HttpMethod.Delete, $"/contacts/{PathSegment.Seg(idOrEmail)}", cancellationToken: cancellationToken);
}

public sealed class ContactSegmentsResource
{
    private readonly INafruHttp _http;
    internal ContactSegmentsResource(INafruHttp http) => _http = http;

    public Task<ListResponse<Segment>> ListAsync(string idOrEmail, ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<Segment>>(HttpMethod.Get, $"/contacts/{PathSegment.Seg(idOrEmail)}/segments", query, cancellationToken: cancellationToken);

    /// <summary>Kişiyi statik segmente ekler (dinamik segmentte 422).</summary>
    public Task<ContactSegmentChange> AddAsync(string idOrEmail, string segmentId, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactSegmentChange>(HttpMethod.Post, $"/contacts/{PathSegment.Seg(idOrEmail)}/segments/{PathSegment.Seg(segmentId)}", cancellationToken: cancellationToken);

    public Task<ContactSegmentChange> RemoveAsync(string idOrEmail, string segmentId, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactSegmentChange>(HttpMethod.Delete, $"/contacts/{PathSegment.Seg(idOrEmail)}/segments/{PathSegment.Seg(segmentId)}", cancellationToken: cancellationToken);
}

public sealed class ContactTopicsResource
{
    private readonly INafruHttp _http;
    internal ContactTopicsResource(INafruHttp http) => _http = http;

    public Task<ListResponse<ContactTopic>> ListAsync(string idOrEmail, ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<ContactTopic>>(HttpMethod.Get, $"/contacts/{PathSegment.Seg(idOrEmail)}/topics", query, cancellationToken: cancellationToken);

    // Sunucu gövdede çıplak dizi bekler.
    public Task<ContactRef> UpdateAsync(string idOrEmail, UpdateContactTopicsInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactRef>(HttpMethod.Patch, $"/contacts/{PathSegment.Seg(idOrEmail)}/topics", body: input.Topics, cancellationToken: cancellationToken);
}

public sealed class ContactPropertiesResource
{
    private readonly INafruHttp _http;
    internal ContactPropertiesResource(INafruHttp http) => _http = http;

    public Task<ContactPropertyRef> CreateAsync(CreateContactPropertyInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactPropertyRef>(HttpMethod.Post, "/contact-properties", body: input, cancellationToken: cancellationToken);

    public Task<ContactPropertyDetail> GetAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactPropertyDetail>(HttpMethod.Get, $"/contact-properties/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<ListResponse<ContactProperty>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<ContactProperty>>(HttpMethod.Get, "/contact-properties", query, cancellationToken: cancellationToken);

    public Task<ContactPropertyRef> UpdateAsync(string id, UpdateContactPropertyInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ContactPropertyRef>(HttpMethod.Patch, $"/contact-properties/{PathSegment.Seg(id)}", body: input, cancellationToken: cancellationToken);

    public Task<DeletedResponse> RemoveAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/contact-properties/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);
}

public sealed class SegmentsResource
{
    private readonly INafruHttp _http;
    internal SegmentsResource(INafruHttp http) => _http = http;

    public Task<SegmentRef> CreateAsync(CreateSegmentInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<SegmentRef>(HttpMethod.Post, "/segments", body: input, cancellationToken: cancellationToken);

    public Task<SegmentDetail> GetAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<SegmentDetail>(HttpMethod.Get, $"/segments/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<ListResponse<Segment>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<Segment>>(HttpMethod.Get, "/segments", query, cancellationToken: cancellationToken);

    public Task<DeletedResponse> RemoveAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/segments/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    /// <summary>Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız <c>After</c>.</summary>
    public Task<ListResponse<Contact>> ContactsAsync(string id, ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<Contact>>(HttpMethod.Get, $"/segments/{PathSegment.Seg(id)}/contacts", query, cancellationToken: cancellationToken);
}

public sealed class TopicsResource
{
    private readonly INafruHttp _http;
    internal TopicsResource(INafruHttp http) => _http = http;

    public Task<TopicRef> CreateAsync(CreateTopicInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TopicRef>(HttpMethod.Post, "/topics", body: input, cancellationToken: cancellationToken);

    public Task<TopicDetail> GetAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TopicDetail>(HttpMethod.Get, $"/topics/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<ListResponse<Topic>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<Topic>>(HttpMethod.Get, "/topics", query, cancellationToken: cancellationToken);

    public Task<TopicRef> UpdateAsync(string id, UpdateTopicInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TopicRef>(HttpMethod.Patch, $"/topics/{PathSegment.Seg(id)}", body: input, cancellationToken: cancellationToken);

    public Task<DeletedResponse> RemoveAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/topics/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);
}

public sealed class BroadcastsResource
{
    private readonly INafruHttp _http;
    internal BroadcastsResource(INafruHttp http) => _http = http;

    /// <summary>Taslak oluşturur; <c>Send = true</c> ile aynı istekte gönderir.</summary>
    public Task<BroadcastRef> CreateAsync(CreateBroadcastInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<BroadcastRef>(HttpMethod.Post, "/broadcasts", body: input, cancellationToken: cancellationToken);

    public Task<Broadcast> GetAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<Broadcast>(HttpMethod.Get, $"/broadcasts/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<ListResponse<BroadcastListItem>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<BroadcastListItem>>(HttpMethod.Get, "/broadcasts", query, cancellationToken: cancellationToken);

    /// <summary>Yalnız taslakta (aksi 409).</summary>
    public Task<BroadcastRef> UpdateAsync(string id, UpdateBroadcastInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<BroadcastRef>(HttpMethod.Patch, $"/broadcasts/{PathSegment.Seg(id)}", body: input, cancellationToken: cancellationToken);

    /// <summary>Yalnız taslakta (aksi 409).</summary>
    public Task<DeletedResponse> RemoveAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/broadcasts/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<BroadcastRef> SendAsync(string id, SendBroadcastInput? input = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<BroadcastRef>(HttpMethod.Post, $"/broadcasts/{PathSegment.Seg(id)}/send", body: input ?? new SendBroadcastInput(), cancellationToken: cancellationToken);

    public Task<BroadcastRef> CancelAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<BroadcastRef>(HttpMethod.Post, $"/broadcasts/{PathSegment.Seg(id)}/cancel", cancellationToken: cancellationToken);
}

/// <summary><c>idOrAlias</c>: kimlik ya da takma ad.</summary>
public sealed class TemplatesResource
{
    private readonly INafruHttp _http;
    internal TemplatesResource(INafruHttp http) => _http = http;

    public Task<TemplateSaved> CreateAsync(CreateTemplateInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TemplateSaved>(HttpMethod.Post, "/templates", body: input, cancellationToken: cancellationToken);

    public Task<Template> GetAsync(string idOrAlias, CancellationToken cancellationToken = default) =>
        _http.SendAsync<Template>(HttpMethod.Get, $"/templates/{PathSegment.Seg(idOrAlias)}", cancellationToken: cancellationToken);

    public Task<ListResponse<TemplateListItem>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<TemplateListItem>>(HttpMethod.Get, "/templates", query, cancellationToken: cancellationToken);

    /// <summary>Taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır.</summary>
    public Task<TemplateSaved> UpdateAsync(string idOrAlias, UpdateTemplateInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TemplateSaved>(HttpMethod.Patch, $"/templates/{PathSegment.Seg(idOrAlias)}", body: input, cancellationToken: cancellationToken);

    public Task<DeletedResponse> RemoveAsync(string idOrAlias, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/templates/{PathSegment.Seg(idOrAlias)}", cancellationToken: cancellationToken);

    public Task<TemplatePublished> PublishAsync(string idOrAlias, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TemplatePublished>(HttpMethod.Post, $"/templates/{PathSegment.Seg(idOrAlias)}/publish", cancellationToken: cancellationToken);

    public Task<TemplateRef> DuplicateAsync(string idOrAlias, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TemplateRef>(HttpMethod.Post, $"/templates/{PathSegment.Seg(idOrAlias)}/duplicate", cancellationToken: cancellationToken);

    /// <summary>Dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır.</summary>
    public Task<TemplateTranslation> PutTranslationAsync(string idOrAlias, string locale, PutTemplateTranslationInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TemplateTranslation>(HttpMethod.Put, $"/templates/{PathSegment.Seg(idOrAlias)}/translations/{PathSegment.Seg(locale)}", body: input, cancellationToken: cancellationToken);

    public Task<TemplateTranslationDeleted> RemoveTranslationAsync(string idOrAlias, string locale, CancellationToken cancellationToken = default) =>
        _http.SendAsync<TemplateTranslationDeleted>(HttpMethod.Delete, $"/templates/{PathSegment.Seg(idOrAlias)}/translations/{PathSegment.Seg(locale)}", cancellationToken: cancellationToken);
}

/// <summary>Çalışma alanının markası: logo, renkler, yazı tipi, altbilgi. Şablonlar markayı <c>Brand</c> alanıyla devralır.</summary>
public sealed class BrandResource
{
    private readonly INafruHttp _http;
    internal BrandResource(INafruHttp http) => _http = http;

    public Task<Brand> GetAsync(CancellationToken cancellationToken = default) =>
        _http.SendAsync<Brand>(HttpMethod.Get, "/brand", cancellationToken: cancellationToken);

    /// <summary>Markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur).</summary>
    public Task<Brand> UpdateAsync(UpdateBrandInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<Brand>(HttpMethod.Put, "/brand", body: input, cancellationToken: cancellationToken);
}

public sealed class WebhooksResource
{
    private readonly INafruHttp _http;
    internal WebhooksResource(INafruHttp http) => _http = http;

    /// <summary>Yanıttaki <c>SigningSecret</c> ile <see cref="NafruWebhook.Verify"/> kullanılır.</summary>
    public Task<CreatedWebhook> CreateAsync(CreateWebhookInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<CreatedWebhook>(HttpMethod.Post, "/webhooks", body: input, cancellationToken: cancellationToken);

    public Task<WebhookDetail> GetAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<WebhookDetail>(HttpMethod.Get, $"/webhooks/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);

    public Task<ListResponse<Webhook>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<Webhook>>(HttpMethod.Get, "/webhooks", query, cancellationToken: cancellationToken);

    public Task<WebhookRef> UpdateAsync(string id, UpdateWebhookInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<WebhookRef>(HttpMethod.Patch, $"/webhooks/{PathSegment.Seg(id)}", body: input, cancellationToken: cancellationToken);

    public Task<DeletedResponse> RemoveAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/webhooks/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);
}

public sealed class ApiKeysResource
{
    private readonly INafruHttp _http;
    internal ApiKeysResource(INafruHttp http) => _http = http;

    public Task<CreatedApiKey> CreateAsync(CreateApiKeyInput input, CancellationToken cancellationToken = default) =>
        _http.SendAsync<CreatedApiKey>(HttpMethod.Post, "/api-keys", body: input, cancellationToken: cancellationToken);

    public Task<ListResponse<ApiKey>> ListAsync(ListQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<ApiKey>>(HttpMethod.Get, "/api-keys", query, cancellationToken: cancellationToken);

    public Task<DeletedResponse> RemoveAsync(string id, CancellationToken cancellationToken = default) =>
        _http.SendAsync<DeletedResponse>(HttpMethod.Delete, $"/api-keys/{PathSegment.Seg(id)}", cancellationToken: cancellationToken);
}

/// <summary>Otomasyonları tetikleyen özel olay API'si.</summary>
public sealed class EventsResource
{
    private readonly INafruHttp _http;
    internal EventsResource(INafruHttp http) => _http = http;

    /// <param name="idempotencyKey"><c>Idempotency-Key</c>: aynı anahtarla yinelenen istek olayı bir kez işler.</param>
    public Task<EventAccepted> SendAsync(SendEventInput input, string? idempotencyKey = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<EventAccepted>(HttpMethod.Post, "/events", body: input, idempotencyKey: idempotencyKey, cancellationToken: cancellationToken);

    /// <summary>En çok 100 olay; biri geçersizse tüm istek 422.</summary>
    public Task<EventBatchResponse> BatchAsync(IReadOnlyList<SendEventInput> input, string? idempotencyKey = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<EventBatchResponse>(HttpMethod.Post, "/events/batch", body: input, idempotencyKey: idempotencyKey, cancellationToken: cancellationToken);

    public Task<ListResponse<EventItem>> ListAsync(ListEventsQuery? query = null, CancellationToken cancellationToken = default) =>
        _http.SendAsync<ListResponse<EventItem>>(HttpMethod.Get, "/events", query, cancellationToken: cancellationToken);
}
