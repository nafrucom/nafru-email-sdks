import Foundation

public struct Emails: Sendable {
    let http: Requester
    let devOutbox: String?

    /// `POST /emails`. `scheduledAt` verilirse zamanlanır; `idempotencyKey` ile yineleme güvenlidir.
    public func send(_ input: SendEmailInput, idempotencyKey: String? = nil) async throws -> SendEmailResponse {
        if let devOutbox { return SendEmailResponse(id: try writeDevEmail(devOutbox, input)) }
        return try await http(.post("/emails", input, idempotencyKey: idempotencyKey))
    }

    /// `POST /emails/batch`: en çok 100 e-posta; ek ve şablon desteklenmez.
    public func batch(_ input: [BatchEmailItem], idempotencyKey: String? = nil) async throws -> BatchEmailResponse {
        if let devOutbox {
            return BatchEmailResponse(data: try input.map { SendEmailResponse(id: try writeDevEmail(devOutbox, $0.asSendInput)) })
        }
        return try await http(.post("/emails/batch", input, idempotencyKey: idempotencyKey))
    }

    public func get(_ id: String) async throws -> Email {
        try await http(.get("/emails/\(seg(id))"))
    }

    public func list(_ query: ListEmailsQuery = .init()) async throws -> ListResponse<EmailListItem> {
        try await http(.get("/emails", query))
    }

    /// Zamanlanmış e-postanın gönderim anını değiştirir.
    public func update(_ id: String, scheduledAt: String) async throws -> EmailRef {
        try await http(.patch("/emails/\(seg(id))", ["scheduled_at": scheduledAt]))
    }

    /// Zamanlanmış e-postayı iptal eder.
    public func cancel(_ id: String) async throws -> EmailRef {
        try await http(.post("/emails/\(seg(id))/cancel"))
    }
}

public struct Domains: Sendable {
    let http: Requester

    public func create(_ input: CreateDomainInput) async throws -> DomainDetail {
        try await http(.post("/domains", input))
    }

    public func get(_ id: String) async throws -> DomainDetail {
        try await http(.get("/domains/\(seg(id))"))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<Domain> {
        try await http(.get("/domains", query))
    }

    public func update(_ id: String, _ input: UpdateDomainInput) async throws -> DomainRef {
        try await http(.patch("/domains/\(seg(id))", input))
    }

    public func remove(_ id: String) async throws -> DeletedResponse {
        try await http(.delete("/domains/\(seg(id))"))
    }

    /// DNS kayıtlarını denetletir; sonuç `get` ile okunur.
    public func verify(_ id: String) async throws -> DomainRef {
        try await http(.post("/domains/\(seg(id))/verify"))
    }
}

/// Kişi uçlarında `id` yerine e-posta adresi de verilebilir.
public struct Contacts: Sendable {
    let http: Requester
    public let segments: ContactSegments
    public let topics: ContactTopics

    init(http: Requester) {
        self.http = http
        segments = ContactSegments(http: http)
        topics = ContactTopics(http: http)
    }

    public func create(_ input: CreateContactInput) async throws -> ContactRef {
        try await http(.post("/contacts", input))
    }

    public func get(_ idOrEmail: String) async throws -> ContactDetail {
        try await http(.get("/contacts/\(seg(idOrEmail))"))
    }

    public func list(_ query: ListContactsQuery = .init()) async throws -> ListResponse<Contact> {
        try await http(.get("/contacts", query))
    }

    public func update(_ idOrEmail: String, _ input: UpdateContactInput) async throws -> ContactRef {
        try await http(.patch("/contacts/\(seg(idOrEmail))", input))
    }

    public func remove(_ idOrEmail: String) async throws -> DeletedContact {
        try await http(.delete("/contacts/\(seg(idOrEmail))"))
    }
}

public struct ContactSegments: Sendable {
    let http: Requester

    public func list(_ idOrEmail: String, _ query: ListQuery = .init()) async throws -> ListResponse<Segment> {
        try await http(.get("/contacts/\(seg(idOrEmail))/segments", query))
    }

    /// Kişiyi statik segmente ekler (dinamik segmentte 422).
    public func add(_ idOrEmail: String, _ segmentId: String) async throws -> SegmentMembership {
        try await http(.post("/contacts/\(seg(idOrEmail))/segments/\(seg(segmentId))"))
    }

    public func remove(_ idOrEmail: String, _ segmentId: String) async throws -> DeletedSegmentMembership {
        try await http(.delete("/contacts/\(seg(idOrEmail))/segments/\(seg(segmentId))"))
    }
}

public struct SegmentMembership: Decodable, Sendable {
    public let id: String
}

public struct DeletedSegmentMembership: Decodable, Sendable {
    public let id: String
    public let deleted: Bool
}

public struct ContactTopics: Sendable {
    let http: Requester

    public func list(_ idOrEmail: String, _ query: ListQuery = .init()) async throws -> ListResponse<ContactTopic> {
        try await http(.get("/contacts/\(seg(idOrEmail))/topics", query))
    }

    public func update(_ idOrEmail: String, _ input: UpdateContactTopicsInput) async throws -> ContactRef {
        // Sunucu gövdede çıplak dizi bekler.
        try await http(.patch("/contacts/\(seg(idOrEmail))/topics", input.topics))
    }
}

public struct ContactProperties: Sendable {
    let http: Requester

    public func create(_ input: CreateContactPropertyInput) async throws -> ContactPropertyRef {
        try await http(.post("/contact-properties", input))
    }

    public func get(_ id: String) async throws -> ContactPropertyDetail {
        try await http(.get("/contact-properties/\(seg(id))"))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<ContactProperty> {
        try await http(.get("/contact-properties", query))
    }

    public func update(_ id: String, _ input: UpdateContactPropertyInput) async throws -> ContactPropertyRef {
        try await http(.patch("/contact-properties/\(seg(id))", input))
    }

    public func remove(_ id: String) async throws -> DeletedResponse {
        try await http(.delete("/contact-properties/\(seg(id))"))
    }
}

public struct Segments: Sendable {
    let http: Requester

    public func create(_ input: CreateSegmentInput) async throws -> SegmentRef {
        try await http(.post("/segments", input))
    }

    public func get(_ id: String) async throws -> SegmentDetail {
        try await http(.get("/segments/\(seg(id))"))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<Segment> {
        try await http(.get("/segments", query))
    }

    public func remove(_ id: String) async throws -> DeletedResponse {
        try await http(.delete("/segments/\(seg(id))"))
    }

    /// Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız `after`.
    public func contacts(_ id: String, _ query: SegmentContactsQuery = .init()) async throws -> ListResponse<Contact> {
        try await http(.get("/segments/\(seg(id))/contacts", query))
    }
}

public struct Topics: Sendable {
    let http: Requester

    public func create(_ input: CreateTopicInput) async throws -> TopicRef {
        try await http(.post("/topics", input))
    }

    public func get(_ id: String) async throws -> TopicDetail {
        try await http(.get("/topics/\(seg(id))"))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<Topic> {
        try await http(.get("/topics", query))
    }

    public func update(_ id: String, _ input: UpdateTopicInput) async throws -> TopicRef {
        try await http(.patch("/topics/\(seg(id))", input))
    }

    public func remove(_ id: String) async throws -> DeletedResponse {
        try await http(.delete("/topics/\(seg(id))"))
    }
}

public struct Broadcasts: Sendable {
    let http: Requester

    /// Taslak oluşturur; `send: true` ile aynı istekte gönderir.
    public func create(_ input: CreateBroadcastInput) async throws -> BroadcastRef {
        try await http(.post("/broadcasts", input))
    }

    public func get(_ id: String) async throws -> Broadcast {
        try await http(.get("/broadcasts/\(seg(id))"))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<BroadcastListItem> {
        try await http(.get("/broadcasts", query))
    }

    /// Yalnız taslakta (aksi 409).
    public func update(_ id: String, _ input: UpdateBroadcastInput) async throws -> BroadcastRef {
        try await http(.patch("/broadcasts/\(seg(id))", input))
    }

    /// Yalnız taslakta (aksi 409).
    public func remove(_ id: String) async throws -> DeletedResponse {
        try await http(.delete("/broadcasts/\(seg(id))"))
    }

    public func send(_ id: String, _ input: SendBroadcastInput = .init()) async throws -> BroadcastRef {
        try await http(.post("/broadcasts/\(seg(id))/send", input))
    }

    public func cancel(_ id: String) async throws -> BroadcastRef {
        try await http(.post("/broadcasts/\(seg(id))/cancel"))
    }
}

public struct Templates: Sendable {
    let http: Requester

    public func create(_ input: CreateTemplateInput) async throws -> TemplateSaved {
        try await http(.post("/templates", input))
    }

    /// `idOrAlias`: kimlik ya da takma ad.
    public func get(_ idOrAlias: String) async throws -> Template {
        try await http(.get("/templates/\(seg(idOrAlias))"))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<TemplateListItem> {
        try await http(.get("/templates", query))
    }

    /// Taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır.
    public func update(_ idOrAlias: String, _ input: UpdateTemplateInput) async throws -> TemplateSaved {
        try await http(.patch("/templates/\(seg(idOrAlias))", input))
    }

    public func remove(_ idOrAlias: String) async throws -> DeletedResponse {
        try await http(.delete("/templates/\(seg(idOrAlias))"))
    }

    public func publish(_ idOrAlias: String) async throws -> TemplatePublished {
        try await http(.post("/templates/\(seg(idOrAlias))/publish"))
    }

    public func duplicate(_ idOrAlias: String) async throws -> TemplateRef {
        try await http(.post("/templates/\(seg(idOrAlias))/duplicate"))
    }

    /// Dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır.
    public func putTranslation(_ idOrAlias: String, locale: String, _ input: PutTemplateTranslationInput) async throws -> TemplateTranslation {
        try await http(.put("/templates/\(seg(idOrAlias))/translations/\(seg(locale))", input))
    }

    public func removeTranslation(_ idOrAlias: String, locale: String) async throws -> TemplateTranslationDeleted {
        try await http(.delete("/templates/\(seg(idOrAlias))/translations/\(seg(locale))"))
    }
}

/// Çalışma alanının markası: logo, renkler, yazı tipi, altbilgi. Şablonlar markayı `brand` alanıyla devralır.
public struct BrandResource: Sendable {
    let http: Requester

    public func get() async throws -> Brand {
        try await http(.get("/brand"))
    }

    /// Markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur).
    public func update(_ input: UpdateBrandInput) async throws -> Brand {
        try await http(.put("/brand", input))
    }
}

public struct Webhooks: Sendable {
    let http: Requester

    /// Yanıttaki `signingSecret` ile `verifyWebhook` kullanılır.
    public func create(_ input: CreateWebhookInput) async throws -> CreatedWebhook {
        try await http(.post("/webhooks", input))
    }

    public func get(_ id: String) async throws -> WebhookDetail {
        try await http(.get("/webhooks/\(seg(id))"))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<Webhook> {
        try await http(.get("/webhooks", query))
    }

    public func update(_ id: String, _ input: UpdateWebhookInput) async throws -> WebhookRef {
        try await http(.patch("/webhooks/\(seg(id))", input))
    }

    public func remove(_ id: String) async throws -> DeletedResponse {
        try await http(.delete("/webhooks/\(seg(id))"))
    }
}

public struct ApiKeys: Sendable {
    let http: Requester

    public func create(_ input: CreateApiKeyInput) async throws -> CreatedApiKey {
        try await http(.post("/api-keys", input))
    }

    public func list(_ query: ListQuery = .init()) async throws -> ListResponse<ApiKey> {
        try await http(.get("/api-keys", query))
    }

    public func remove(_ id: String) async throws -> DeletedResponse {
        try await http(.delete("/api-keys/\(seg(id))"))
    }
}

/// Otomasyonları tetikleyen özel olay API'si.
public struct Events: Sendable {
    let http: Requester

    /// `idempotencyKey`: aynı anahtarla yinelenen istek olayı bir kez işler.
    public func send(_ input: SendEventInput, idempotencyKey: String? = nil) async throws -> EventAccepted {
        try await http(.post("/events", input, idempotencyKey: idempotencyKey))
    }

    /// En çok 100 olay; biri geçersizse tüm istek 422.
    public func batch(_ input: [SendEventInput], idempotencyKey: String? = nil) async throws -> EventBatchResponse {
        try await http(.post("/events/batch", input, idempotencyKey: idempotencyKey))
    }

    public func list(_ query: ListEventsQuery = .init()) async throws -> ListResponse<EventItem> {
        try await http(.get("/events", query))
    }
}

/// `NafruConnection.Emails` kendi `Emails` adını gölgelediği için (modül adıyla nitelemek tipe çözülür).
typealias EmailsResource = Emails
