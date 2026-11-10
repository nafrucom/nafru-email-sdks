import Foundation

private struct TypeKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// Tekrar kuralı; saat (`HH:MM`) çalışma alanının saat dilimindedir. `weekly.days`: 0 = pazar … 6 = cumartesi.
/// `monthly.day`: 1–31 (ay kısaysa ayın son günü). `interval.everyDays`: 1–365 gün.
public enum BroadcastRecurrence: Codable, Sendable, Equatable {
    case weekly(days: [Int], time: String)
    case monthly(day: Int, time: String)
    case interval(everyDays: Int, time: String)
    /// Bu SDK sürümünün tanımadığı yeni kural türü (çözümleme kırılmasın diye).
    case unknown(type: String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        let type = try c.decode(String.self, forKey: TypeKey("type"))
        switch type {
        case "weekly": self = .weekly(days: try c.decode([Int].self, forKey: TypeKey("days")), time: try c.decode(String.self, forKey: TypeKey("time")))
        case "monthly": self = .monthly(day: try c.decode(Int.self, forKey: TypeKey("day")), time: try c.decode(String.self, forKey: TypeKey("time")))
        case "interval": self = .interval(everyDays: try c.decode(Int.self, forKey: TypeKey("every_days")), time: try c.decode(String.self, forKey: TypeKey("time")))
        default: self = .unknown(type: type)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .weekly(let days, let time):
            try c.encode("weekly", forKey: TypeKey("type"))
            try c.encode(days, forKey: TypeKey("days"))
            try c.encode(time, forKey: TypeKey("time"))
        case .monthly(let day, let time):
            try c.encode("monthly", forKey: TypeKey("type"))
            try c.encode(day, forKey: TypeKey("day"))
            try c.encode(time, forKey: TypeKey("time"))
        case .interval(let everyDays, let time):
            try c.encode("interval", forKey: TypeKey("type"))
            try c.encode(everyDays, forKey: TypeKey("every_days"))
            try c.encode(time, forKey: TypeKey("time"))
        case .unknown(let type):
            try c.encode(type, forKey: TypeKey("type"))
        }
    }
}

/// `{{{data.*}}}` değişkenlerinin kaynağı. `url`: gönderim anında `GET` (https, ≤ 256 KB JSON nesne, 10 sn). `webhook`: imzalı tetik ucu.
public enum BroadcastDataSourceInput: Encodable, Sendable, Equatable {
    case manual
    /// `headerName`/`headerValue`: `nil` göndermez, `.some(nil)` temizler.
    case url(String, headerName: String?? = nil, headerValue: String?? = nil)
    case webhook(regenerateSecret: Bool? = nil)

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .manual:
            try c.encode("manual", forKey: TypeKey("type"))
        case .url(let url, let headerName, let headerValue):
            try c.encode("url", forKey: TypeKey("type"))
            try c.encode(url, forKey: TypeKey("url"))
            if let headerName { try c.encode(headerName, forKey: TypeKey("header_name")) }
            if let headerValue { try c.encode(headerValue, forKey: TypeKey("header_value")) }
        case .webhook(let regenerateSecret):
            try c.encode("webhook", forKey: TypeKey("type"))
            try c.encodeIfPresent(regenerateSecret, forKey: TypeKey("regenerate_secret"))
        }
    }
}

public enum BroadcastDataSource: Decodable, Sendable, Equatable {
    case manual
    case url(String, headerName: String?, hasHeaderValue: Bool)
    case webhook(triggerUrl: String, secret: String)
    /// Bu SDK sürümünün tanımadığı yeni kaynak türü.
    case unknown(type: String)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TypeKey.self)
        let type = try c.decode(String.self, forKey: TypeKey("type"))
        switch type {
        case "manual": self = .manual
        case "url":
            self = .url(
                try c.decode(String.self, forKey: TypeKey("url")),
                headerName: try c.decodeIfPresent(String.self, forKey: TypeKey("header_name")),
                hasHeaderValue: try c.decodeIfPresent(Bool.self, forKey: TypeKey("has_header_value")) ?? false
            )
        case "webhook":
            self = .webhook(triggerUrl: try c.decode(String.self, forKey: TypeKey("trigger_url")), secret: try c.decode(String.self, forKey: TypeKey("secret")))
        default: self = .unknown(type: type)
        }
    }
}
