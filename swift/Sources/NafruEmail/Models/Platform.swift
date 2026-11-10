import Foundation

// Webhook'lar, API anahtarları, olaylar ve "Nafru ile bağlan" tipleri.

public struct WebhookEventType: NafruStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let emailSent: Self = "email.sent"
    public static let emailScheduled: Self = "email.scheduled"
    public static let emailDelivered: Self = "email.delivered"
    public static let emailDeliveryDelayed: Self = "email.delivery_delayed"
    public static let emailComplained: Self = "email.complained"
    public static let emailBounced: Self = "email.bounced"
    public static let emailOpened: Self = "email.opened"
    public static let emailClicked: Self = "email.clicked"
    public static let emailReceived: Self = "email.received"
    public static let emailFailed: Self = "email.failed"
    public static let emailSuppressed: Self = "email.suppressed"
    public static let contactCreated: Self = "contact.created"
    public static let contactUpdated: Self = "contact.updated"
    public static let contactDeleted: Self = "contact.deleted"
    public static let contactTopicsUpdated: Self = "contact.topics.updated"
    public static let domainCreated: Self = "domain.created"
    public static let domainUpdated: Self = "domain.updated"
    public static let domainDeleted: Self = "domain.deleted"
    public static let suppressionAdded: Self = "suppression.added"
    public static let suppressionRemoved: Self = "suppression.removed"
    public static let topicCreated: Self = "topic.created"
    public static let topicUpdated: Self = "topic.updated"
    public static let topicDeleted: Self = "topic.deleted"
}

public struct Webhook: Decodable, Sendable, Identifiable {
    public let id: String
    public let endpoint: String
    public let createdAt: String
    /// `enabled` ya da `disabled`.
    public let status: String
    public let events: [WebhookEventType]

    enum CodingKeys: String, CodingKey {
        case id, endpoint, status, events
        case createdAt = "created_at"
    }
}

public struct WebhookDetail: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let endpoint: String
    public let createdAt: String
    public let status: String
    public let events: [WebhookEventType]
    public let signingSecret: String

    enum CodingKeys: String, CodingKey {
        case object, id, endpoint, status, events
        case createdAt = "created_at"
        case signingSecret = "signing_secret"
    }
}

public struct CreateWebhookInput: Encodable, Sendable {
    /// Herkese açık https adresi.
    public var endpoint: String
    public var events: [WebhookEventType]

    public init(endpoint: String, events: [WebhookEventType]) {
        self.endpoint = endpoint
        self.events = events
    }
}

public struct CreatedWebhook: Decodable, Sendable {
    public let object: String
    public let id: String
    /// Yalnız bu yanıtta ve ayrıntıda görünür; `verifyWebhook` bununla doğrular.
    public let signingSecret: String

    enum CodingKeys: String, CodingKey {
        case object, id
        case signingSecret = "signing_secret"
    }
}

public struct UpdateWebhookInput: Encodable, Sendable {
    public var endpoint: String?
    public var events: [WebhookEventType]?
    public var status: String?

    public init(endpoint: String? = nil, events: [WebhookEventType]? = nil, status: String? = nil) {
        self.endpoint = endpoint
        self.events = events
        self.status = status
    }
}

/// Webhook gövdesi: `{ type, created_at, data }`. Ham gövdeyi önce `verifyWebhook` ile doğrulayın.
public struct WebhookPayload<Payload: Decodable & Sendable>: Decodable, Sendable {
    public let type: WebhookEventType
    public let createdAt: String
    public let data: Payload

    enum CodingKeys: String, CodingKey {
        case type, data
        case createdAt = "created_at"
    }
}

public struct ApiKeyPermission: NafruStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let fullAccess: Self = "full_access"
    public static let sendingAccess: Self = "sending_access"
}

public struct ApiKey: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let createdAt: String
    public let lastUsedAt: String?
    public let permission: ApiKeyPermission
    public let domainId: String?
    public let tokenPrefix: String

    enum CodingKeys: String, CodingKey {
        case id, name, permission
        case createdAt = "created_at"
        case lastUsedAt = "last_used_at"
        case domainId = "domain_id"
        case tokenPrefix = "token_prefix"
    }
}

public struct CreateApiKeyInput: Encodable, Sendable {
    public var name: String
    /// Varsayılan `full_access`.
    public var permission: ApiKeyPermission?
    /// Yalnız `sending_access` ile: anahtarı bu alan adına kısıtlar.
    public var domainId: String?

    public init(name: String, permission: ApiKeyPermission? = nil, domainId: String? = nil) {
        self.name = name
        self.permission = permission
        self.domainId = domainId
    }

    enum CodingKeys: String, CodingKey {
        case name, permission
        case domainId = "domain_id"
    }
}

public struct CreatedApiKey: Decodable, Sendable {
    public let id: String
    /// Tam anahtar yalnız bir kez görünür.
    public let token: String
}

/// Olayın kişisi: e-postayla verilen kişi yoksa oluşturulur; kimlikle verilen yoksa 404.
public enum EventContact: Encodable, Sendable {
    case email(String)
    case id(String)

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .email(let email): try ["email": email].encode(to: encoder)
        case .id(let id): try ["id": id].encode(to: encoder)
        }
    }
}

public struct SendEventInput: Encodable, Sendable {
    /// `^[a-z0-9_.:-]{1,64}$`; `email.`, `contact.`, `segment.`, `topic.`, `automation.` ön ekleri ayrılmıştır.
    public var name: String
    public var contact: EventContact
    public var properties: [String: JSONValue]?
    /// ISO 8601; verilmezse alma anı.
    public var occurredAt: String?
    /// Yalnız kişi bu istekle oluşturuluyorsa: kişiyi abonelikten çıkmış açar.
    public var unsubscribed: Bool?

    public init(name: String, contact: EventContact, properties: [String: JSONValue]? = nil, occurredAt: String? = nil, unsubscribed: Bool? = nil) {
        self.name = name
        self.contact = contact
        self.properties = properties
        self.occurredAt = occurredAt
        self.unsubscribed = unsubscribed
    }

    enum CodingKeys: String, CodingKey {
        case name, contact, properties, unsubscribed
        case occurredAt = "occurred_at"
    }
}

public struct EventAccepted: Decodable, Sendable, Identifiable {
    public let id: String
}

public struct EventBatchResponse: Decodable, Sendable {
    public let data: [EventAccepted]
}

public struct EventItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let contactId: String
    public let email: String
    public let properties: [String: JSONValue]
    /// `api` ya da `system`.
    public let source: String
    public let occurredAt: String
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, email, properties, source
        case contactId = "contact_id"
        case occurredAt = "occurred_at"
        case createdAt = "created_at"
    }
}

public struct ListEventsQuery: PageableQuery {
    public var limit: Int?
    public var after: String?
    public var before: String?
    /// Tam eşleşme; sistem olay adlarını (`email.opened`) da kabul eder.
    public var name: String?
    public var contactId: String?
    /// `contactId` ile birlikte verilmez.
    public var email: String?

    public init(limit: Int? = nil, after: String? = nil, before: String? = nil, name: String? = nil, contactId: String? = nil, email: String? = nil) {
        self.limit = limit
        self.after = after
        self.before = before
        self.name = name
        self.contactId = contactId
        self.email = email
    }

    public var queryItems: [URLQueryItem] {
        nonEmptyQueryItems([
            ("limit", limit.map(String.init)), ("after", after), ("before", before),
            ("name", name), ("contact_id", contactId), ("email", email)
        ])
    }
}

/// Uygulamanın müşteriden isteyebileceği izinler.
public struct AppScope: NafruStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let emailsSend: Self = "emails.send"
    public static let emailsRead: Self = "emails.read"
    public static let templatesRead: Self = "templates.read"
    public static let domainsRead: Self = "domains.read"
    public static let sendersRead: Self = "senders.read"
    public static let connectionRead: Self = "connection.read"
}

public struct AuthorizeUrl: Sendable {
    public let url: String
    /// Yalnız bu bağlanma denemesi için; `exchange` çağrısına kadar sunucunuzda (oturumda) saklayın, tarayıcıya vermeyin.
    public let codeVerifier: String
}

public struct ConnectionGrant: Sendable, Equatable {
    /// `conn_…`: müşteri bağlantısının kalıcı kimliği (kendi veritabanınızda müşteriyle eşleyin).
    public let connectionId: String
    /// Şifreleyerek saklayın; tarayıcıya vermeyin. Her yenilemede değişir (`onTokenRefresh`).
    public let refreshToken: String
    public let scopes: [AppScope]
}

public struct ConnectionTokens: Sendable, Equatable {
    public let refreshToken: String
}

public struct ConnectionOptions: Sendable {
    public var refreshToken: String
    /// Yenileme belirteci döndüğünde çağrılır; yeni değeri KALICI olarak yazmadan eskisi geçersizdir.
    /// Hata fırlatırsa çağrı `token_persist_failed` ile döner.
    public var onTokenRefresh: @Sendable (ConnectionTokens) async throws -> Void

    public init(refreshToken: String, onTokenRefresh: @escaping @Sendable (ConnectionTokens) async throws -> Void) {
        self.refreshToken = refreshToken
        self.onTokenRefresh = onTokenRefresh
    }
}

public struct ConnectionWorkspace: Decodable, Sendable {
    public let name: String
}

public struct ConnectionStatus: Decodable, Sendable {
    public let object: String
    public let id: String
    public let ready: Bool
    /// Hazır olmak için müşterinin tamamlaması gerekenler: `domain`, `sender`, `plan`.
    public let missing: [String]
    public let hints: [String]
    public let scopes: [AppScope]
    /// `customer_pays` ya da `app_pays`.
    public let billingMode: String
    public let setupUrl: String
    public let workspace: ConnectionWorkspace

    enum CodingKeys: String, CodingKey {
        case object, id, ready, missing, hints, scopes, workspace
        case billingMode = "billing_mode"
        case setupUrl = "setup_url"
    }
}

public struct ConnectionDomain: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
}

public struct ConnectionSenders: Decodable, Sendable {
    public let domains: [ConnectionDomain]
    public let defaultFrom: String?

    enum CodingKeys: String, CodingKey {
        case domains
        case defaultFrom = "default_from"
    }
}

public struct ConnectionTemplate: Decodable, Sendable {
    public let key: String
    public let name: String
    /// `workspace` ya da `pack`.
    public let source: String
    public let customizedFromPack: Bool

    enum CodingKeys: String, CodingKey {
        case key, name, source
        case customizedFromPack = "customized_from_pack"
    }
}
