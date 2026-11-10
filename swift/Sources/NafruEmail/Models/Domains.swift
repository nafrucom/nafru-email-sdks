import Foundation

public struct DomainRecord: Decodable, Sendable {
    /// `SPF`, `DKIM`, `Tracking`.
    public let record: String
    public let name: String
    /// `MX`, `TXT`, `CNAME`.
    public let type: String
    public let value: String
    public let ttl: String
    public let status: String
    public let priority: Int?
}

public struct DomainCapabilities: Decodable, Sendable {
    public let sending: String
    public let receiving: String
}

public struct Domain: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    /// `not_started`, `pending`, `verified`, `failed`, `temporary_failure`.
    public let status: String
    public let createdAt: String
    public let region: String
    public let capabilities: DomainCapabilities
    public let openTracking: Bool
    public let clickTracking: Bool
    /// `opportunistic` ya da `enforced`.
    public let tls: String
    public let trackingSubdomain: String?

    enum CodingKeys: String, CodingKey {
        case id, name, status, region, capabilities, tls
        case createdAt = "created_at"
        case openTracking = "open_tracking"
        case clickTracking = "click_tracking"
        case trackingSubdomain = "tracking_subdomain"
    }
}

public struct DomainDetail: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let name: String
    public let status: String
    public let createdAt: String
    public let region: String
    public let capabilities: DomainCapabilities
    public let openTracking: Bool
    public let clickTracking: Bool
    public let tls: String
    public let trackingSubdomain: String?
    public let records: [DomainRecord]

    enum CodingKeys: String, CodingKey {
        case object, id, name, status, region, capabilities, tls, records
        case createdAt = "created_at"
        case openTracking = "open_tracking"
        case clickTracking = "click_tracking"
        case trackingSubdomain = "tracking_subdomain"
    }
}

public struct CreateDomainInput: Encodable, Sendable {
    public var name: String
    public var region: String?
    public var openTracking: Bool?
    public var clickTracking: Bool?
    public var tls: String?
    /// Örn. `track` → `track.<alan-adı>`.
    public var trackingSubdomain: String?

    public init(name: String, region: String? = nil, openTracking: Bool? = nil, clickTracking: Bool? = nil, tls: String? = nil, trackingSubdomain: String? = nil) {
        self.name = name
        self.region = region
        self.openTracking = openTracking
        self.clickTracking = clickTracking
        self.tls = tls
        self.trackingSubdomain = trackingSubdomain
    }

    enum CodingKeys: String, CodingKey {
        case name, region, tls
        case openTracking = "open_tracking"
        case clickTracking = "click_tracking"
        case trackingSubdomain = "tracking_subdomain"
    }
}

public struct UpdateDomainInput: Encodable, Sendable {
    public var openTracking: Bool?
    public var clickTracking: Bool?
    public var tls: String?
    public var trackingSubdomain: String??

    public init(openTracking: Bool? = nil, clickTracking: Bool? = nil, tls: String? = nil, trackingSubdomain: String?? = nil) {
        self.openTracking = openTracking
        self.clickTracking = clickTracking
        self.tls = tls
        self.trackingSubdomain = trackingSubdomain
    }

    enum CodingKeys: String, CodingKey {
        case tls
        case openTracking = "open_tracking"
        case clickTracking = "click_tracking"
        case trackingSubdomain = "tracking_subdomain"
    }
}
