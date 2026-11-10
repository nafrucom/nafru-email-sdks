import Foundation

public struct TopicSubscription: NafruStringValue {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let optIn: TopicSubscription = "opt_in"
    public static let optOut: TopicSubscription = "opt_out"
}

public struct Contact: Decodable, Sendable, Identifiable {
    public let id: String
    public let email: String
    public let firstName: String?
    public let lastName: String?
    public let unsubscribed: Bool
    /// ISO 639-1 ana dil kodu.
    public let locale: String?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, email, unsubscribed, locale
        case firstName = "first_name"
        case lastName = "last_name"
        case createdAt = "created_at"
    }
}

public struct ContactPropertyValue: Decodable, Sendable {
    /// `string` ya da `number`.
    public let type: String
    public let value: JSONValue
}

public struct ContactDetail: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let email: String
    public let firstName: String?
    public let lastName: String?
    public let unsubscribed: Bool
    public let locale: String?
    public let createdAt: String
    /// Yalnız değeri olan alanlar: `{ anahtar: { type, value } }`.
    public let properties: [String: ContactPropertyValue]

    enum CodingKeys: String, CodingKey {
        case object, id, email, unsubscribed, locale, properties
        case firstName = "first_name"
        case lastName = "last_name"
        case createdAt = "created_at"
    }
}

public struct ContactSegmentInput: Encodable, Sendable {
    public var id: String
    public init(id: String) { self.id = id }
}

public struct TopicSubscriptionInput: Encodable, Sendable {
    public var id: String
    public var subscription: TopicSubscription

    public init(id: String, subscription: TopicSubscription) {
        self.id = id
        self.subscription = subscription
    }
}

public struct CreateContactInput: Encodable, Sendable {
    public var email: String
    public var firstName: String??
    public var lastName: String??
    public var unsubscribed: Bool?
    /// ISO 639-1; bölgeli kod (`pt-BR`) sunucuda ana dile indirgenir.
    public var locale: String??
    /// Değer metin, sayı ya da `.null`.
    public var properties: [String: JSONValue]?
    public var segments: [ContactSegmentInput]?
    public var topics: [TopicSubscriptionInput]?

    public init(
        email: String, firstName: String?? = nil, lastName: String?? = nil, unsubscribed: Bool? = nil, locale: String?? = nil,
        properties: [String: JSONValue]? = nil, segments: [ContactSegmentInput]? = nil, topics: [TopicSubscriptionInput]? = nil
    ) {
        self.email = email
        self.firstName = firstName
        self.lastName = lastName
        self.unsubscribed = unsubscribed
        self.locale = locale
        self.properties = properties
        self.segments = segments
        self.topics = topics
    }

    enum CodingKeys: String, CodingKey {
        case email, unsubscribed, locale, properties, segments, topics
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

public struct UpdateContactInput: Encodable, Sendable {
    public var firstName: String??
    public var lastName: String??
    public var unsubscribed: Bool?
    public var locale: String??
    public var properties: [String: JSONValue]?

    public init(firstName: String?? = nil, lastName: String?? = nil, unsubscribed: Bool? = nil, locale: String?? = nil, properties: [String: JSONValue]? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.unsubscribed = unsubscribed
        self.locale = locale
        self.properties = properties
    }

    enum CodingKeys: String, CodingKey {
        case unsubscribed, locale, properties
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

public struct ListContactsQuery: PageableQuery {
    public var limit: Int?
    public var after: String?
    public var before: String?
    /// E-posta, ad ya da soyad içinde arar.
    public var search: String?

    public init(limit: Int? = nil, after: String? = nil, before: String? = nil, search: String? = nil) {
        self.limit = limit
        self.after = after
        self.before = before
        self.search = search
    }

    public var queryItems: [URLQueryItem] {
        nonEmptyQueryItems([("limit", limit.map(String.init)), ("after", after), ("before", before), ("search", search)])
    }
}

public struct DeletedContact: Decodable, Sendable {
    public let object: String
    public let contact: String
    public let deleted: Bool
}

public struct ContactProperty: Decodable, Sendable, Identifiable {
    public let id: String
    public let key: String
    public let type: String
    public let fallbackValue: JSONValue?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, key, type
        case fallbackValue = "fallback_value"
        case createdAt = "created_at"
    }
}

public struct ContactPropertyDetail: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let key: String
    public let type: String
    public let fallbackValue: JSONValue?
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case object, id, key, type
        case fallbackValue = "fallback_value"
        case createdAt = "created_at"
    }
}

public struct CreateContactPropertyInput: Encodable, Sendable {
    public var key: String
    /// `string` ya da `number`.
    public var type: String
    /// `nil` gönderilmez; `.null` açıkça boşaltır.
    public var fallbackValue: JSONValue?

    public init(key: String, type: String, fallbackValue: JSONValue? = nil) {
        self.key = key
        self.type = type
        self.fallbackValue = fallbackValue
    }

    enum CodingKeys: String, CodingKey {
        case key, type
        case fallbackValue = "fallback_value"
    }
}

public struct UpdateContactPropertyInput: Encodable, Sendable {
    public var fallbackValue: JSONValue?

    public init(fallbackValue: JSONValue? = nil) { self.fallbackValue = fallbackValue }

    enum CodingKeys: String, CodingKey {
        case fallbackValue = "fallback_value"
    }
}
