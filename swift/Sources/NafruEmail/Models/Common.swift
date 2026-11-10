import Foundation

// Alanlar Swift'te camelCase, ağda API'deki gibi snake_case (`CodingKeys`).
// `String??` gibi çift isteğe bağlı alanlarda `nil` alanı göndermez, `.some(nil)` açıkça `null` gönderir (değeri temizler).

/// Sunucunun `{ object: 'list', data, has_more }` liste zarfı.
public struct ListResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    public let object: String
    public let data: [Item]
    public let hasMore: Bool

    enum CodingKeys: String, CodingKey {
        case object, data
        case hasMore = "has_more"
    }
}

/// İmleçli liste sorgusu: `after` ve `before` birlikte verilemez.
public struct ListQuery: PageableQuery {
    /// 1–100, varsayılan 20.
    public var limit: Int?
    /// Bu kimlikten sonraki kayıtlar.
    public var after: String?
    /// Bu kimlikten önceki kayıtlar.
    public var before: String?

    public init(limit: Int? = nil, after: String? = nil, before: String? = nil) {
        self.limit = limit
        self.after = after
        self.before = before
    }

    public var queryItems: [URLQueryItem] {
        nonEmptyQueryItems([("limit", limit.map(String.init)), ("after", after), ("before", before)])
    }
}

public struct DeletedResponse: Decodable, Sendable {
    public let object: String
    public let id: String
    public let deleted: Bool
}

/// `{ object, id }` yanıtı (`DomainRef`, `ContactRef`, `EmailRef`, …).
public struct ObjectRef: Decodable, Sendable {
    public let object: String
    public let id: String
}

public typealias DomainRef = ObjectRef
public typealias ContactRef = ObjectRef
public typealias ContactPropertyRef = ObjectRef
public typealias EmailRef = ObjectRef
public typealias TopicRef = ObjectRef
public typealias BroadcastRef = ObjectRef
public typealias TemplateRef = ObjectRef
public typealias WebhookRef = ObjectRef

public struct Tag: Codable, Hashable, Sendable {
    public var name: String
    public var value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}
