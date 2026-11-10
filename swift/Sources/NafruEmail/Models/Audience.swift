import Foundation

// Segmentler, konular ve kampanyalar.

public struct Segment: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let createdAt: String
    /// `static` ya da `dynamic`.
    public let type: String
    public let filter: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case id, name, type, filter
        case createdAt = "created_at"
    }
}

public struct SegmentDetail: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let name: String
    public let createdAt: String
    public let type: String
    public let filter: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case object, id, name, type, filter
        case createdAt = "created_at"
    }
}

public struct CreateSegmentInput: Encodable, Sendable {
    public var name: String
    /// Verilirse dinamik segment.
    public var filter: [String: JSONValue]?

    public init(name: String, filter: [String: JSONValue]? = nil) {
        self.name = name
        self.filter = filter
    }
}

public struct SegmentRef: Decodable, Sendable {
    public let object: String
    public let id: String
    public let name: String
}

/// Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız `after`.
public struct SegmentContactsQuery: PageableQuery {
    public var limit: Int?
    public var after: String?

    public init(limit: Int? = nil, after: String? = nil) {
        self.limit = limit
        self.after = after
    }

    public var queryItems: [URLQueryItem] {
        nonEmptyQueryItems([("limit", limit.map(String.init)), ("after", after)])
    }
}

public struct Topic: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let defaultSubscription: TopicSubscription
    /// `public` ya da `private`.
    public let visibility: String
    public let doubleOptIn: Bool
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, name, description, visibility
        case defaultSubscription = "default_subscription"
        case doubleOptIn = "double_opt_in"
        case createdAt = "created_at"
    }
}

public struct TopicDetail: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let name: String
    public let description: String?
    public let defaultSubscription: TopicSubscription
    public let visibility: String
    public let doubleOptIn: Bool
    public let createdAt: String

    enum CodingKeys: String, CodingKey {
        case object, id, name, description, visibility
        case defaultSubscription = "default_subscription"
        case doubleOptIn = "double_opt_in"
        case createdAt = "created_at"
    }
}

public struct CreateTopicInput: Encodable, Sendable {
    public var name: String
    public var defaultSubscription: TopicSubscription
    public var description: String??
    public var visibility: String?
    public var doubleOptIn: Bool?

    public init(name: String, defaultSubscription: TopicSubscription, description: String?? = nil, visibility: String? = nil, doubleOptIn: Bool? = nil) {
        self.name = name
        self.defaultSubscription = defaultSubscription
        self.description = description
        self.visibility = visibility
        self.doubleOptIn = doubleOptIn
    }

    enum CodingKeys: String, CodingKey {
        case name, description, visibility
        case defaultSubscription = "default_subscription"
        case doubleOptIn = "double_opt_in"
    }
}

public struct UpdateTopicInput: Encodable, Sendable {
    public var name: String?
    public var description: String??
    public var visibility: String?
    public var doubleOptIn: Bool?

    public init(name: String? = nil, description: String?? = nil, visibility: String? = nil, doubleOptIn: Bool? = nil) {
        self.name = name
        self.description = description
        self.visibility = visibility
        self.doubleOptIn = doubleOptIn
    }

    enum CodingKeys: String, CodingKey {
        case name, description, visibility
        case doubleOptIn = "double_opt_in"
    }
}

public struct ContactTopic: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let description: String?
    public let subscription: TopicSubscription
    /// `opt_in`, `opt_out` ya da `pending` (çift onay bekliyor; `subscription` bu durumda `opt_out` görünür).
    public let status: String
}

public struct UpdateContactTopicsInput: Sendable {
    public var topics: [TopicSubscriptionInput]

    public init(topics: [TopicSubscriptionInput]) { self.topics = topics }
}

public struct BroadcastListItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let segmentId: String
    public let audienceId: String
    public let subject: String
    /// `draft`, `scheduled`, `sending`, `sent`, `paused`, `canceled`, `failed`.
    public let status: String
    public let createdAt: String
    public let scheduledAt: String?
    public let sentAt: String?
    /// Tekrar kuralı (şablon kaydında); yoksa `nil`.
    public let recurrence: BroadcastRecurrence?
    /// Şablonun tetik durumu: `active`, `paused`; `nil` = başlatılmadı.
    public let triggerState: String?
    /// Sonraki zamanlı çalışma (ISO 8601).
    public let nextRunAt: String?
    /// Çalışma örneğinde şablonun kimliği.
    public let parentId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, subject, status
        case segmentId = "segment_id"
        case audienceId = "audience_id"
        case createdAt = "created_at"
        case scheduledAt = "scheduled_at"
        case sentAt = "sent_at"
        case recurrence
        case triggerState = "trigger_state"
        case nextRunAt = "next_run_at"
        case parentId = "parent_id"
    }
}

public struct Broadcast: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let name: String
    public let segmentId: String
    public let audienceId: String
    public let subject: String
    public let status: String
    public let createdAt: String
    public let scheduledAt: String?
    public let sentAt: String?
    /// Tekrar kuralı (şablon kaydında); yoksa `nil`.
    public let recurrence: BroadcastRecurrence?
    /// Şablonun tetik durumu: `active`, `paused`; `nil` = başlatılmadı.
    public let triggerState: String?
    /// Sonraki zamanlı çalışma (ISO 8601).
    public let nextRunAt: String?
    /// Çalışma örneğinde şablonun kimliği.
    public let parentId: String?
    public let from: String
    public let replyTo: [String]?
    public let previewText: String?
    public let topicId: String?
    public let templateId: String?
    public let html: String?
    public let text: String?
    public let openTracking: Bool
    public let clickTracking: Bool
    public let finishedAt: String?
    public let failureReason: String?
    /// Şablondaki `{{{data.*}}}` bağlamı (gönderilmiş örnekte gönderim anında çözülen değer).
    public let data: [String: JSONValue]?
    public let dataSource: BroadcastDataSource?

    enum CodingKeys: String, CodingKey {
        case object, id, name, subject, status, from, html, text
        case segmentId = "segment_id"
        case audienceId = "audience_id"
        case createdAt = "created_at"
        case scheduledAt = "scheduled_at"
        case sentAt = "sent_at"
        case recurrence
        case triggerState = "trigger_state"
        case nextRunAt = "next_run_at"
        case parentId = "parent_id"
        case replyTo = "reply_to"
        case previewText = "preview_text"
        case topicId = "topic_id"
        case templateId = "template_id"
        case openTracking = "open_tracking"
        case clickTracking = "click_tracking"
        case finishedAt = "finished_at"
        case failureReason = "failure_reason"
        case data
        case dataSource = "data_source"
    }
}

public struct CreateBroadcastInput: Encodable, Sendable {
    /// Boşsa konu satırı.
    public var name: String?
    public var segmentId: String
    public var topicId: String?
    public var from: String
    public var subject: String?
    public var replyTo: [String]?
    public var html: String?
    public var text: String?
    /// Şablon kimliği ya da takma adı; `html`/`text` ile birlikte verilmez.
    public var templateId: String?
    public var previewText: String??
    /// `true`: aynı istekte gönderir. `scheduledAt` yalnız bununla anlamlıdır.
    public var send: Bool?
    public var scheduledAt: String?
    public var openTracking: Bool?
    public var clickTracking: Bool?
    /// `{{{data.*}}}` değişkenlerinin değeri (JSON nesne, ≤ 256 KB).
    public var data: [String: JSONValue]??
    public var dataSource: BroadcastDataSourceInput??
    /// Verilirse kayıt tekrarlayan bir şablondur: `send` onu etkinleştirir; her çalışma yeni bir toplu gönderim oluşturur.
    public var recurrence: BroadcastRecurrence??

    public init(
        name: String? = nil, segmentId: String, topicId: String? = nil, from: String, subject: String? = nil, replyTo: [String]? = nil,
        html: String? = nil, text: String? = nil, templateId: String? = nil, previewText: String?? = nil, send: Bool? = nil,
        scheduledAt: String? = nil, openTracking: Bool? = nil, clickTracking: Bool? = nil,
        data: [String: JSONValue]?? = nil, dataSource: BroadcastDataSourceInput?? = nil, recurrence: BroadcastRecurrence?? = nil
    ) {
        self.name = name
        self.segmentId = segmentId
        self.topicId = topicId
        self.from = from
        self.subject = subject
        self.replyTo = replyTo
        self.html = html
        self.text = text
        self.templateId = templateId
        self.previewText = previewText
        self.send = send
        self.scheduledAt = scheduledAt
        self.openTracking = openTracking
        self.clickTracking = clickTracking
        self.data = data
        self.dataSource = dataSource
        self.recurrence = recurrence
    }

    enum CodingKeys: String, CodingKey {
        case name, from, subject, html, text, send
        case segmentId = "segment_id"
        case topicId = "topic_id"
        case replyTo = "reply_to"
        case templateId = "template_id"
        case previewText = "preview_text"
        case scheduledAt = "scheduled_at"
        case openTracking = "open_tracking"
        case clickTracking = "click_tracking"
        case data, recurrence
        case dataSource = "data_source"
    }
}

public struct UpdateBroadcastInput: Encodable, Sendable {
    public var name: String?
    public var segmentId: String?
    public var topicId: String??
    public var from: String?
    public var subject: String?
    public var replyTo: [String]?
    public var html: String?
    public var text: String?
    public var previewText: String??
    public var openTracking: Bool?
    public var clickTracking: Bool?
    /// `{{{data.*}}}` değişkenlerinin değeri (JSON nesne, ≤ 256 KB).
    public var data: [String: JSONValue]??
    public var dataSource: BroadcastDataSourceInput??
    /// Verilirse kayıt tekrarlayan bir şablondur: `send` onu etkinleştirir; her çalışma yeni bir toplu gönderim oluşturur.
    public var recurrence: BroadcastRecurrence??

    public init(
        name: String? = nil, segmentId: String? = nil, topicId: String?? = nil, from: String? = nil, subject: String? = nil,
        replyTo: [String]? = nil, html: String? = nil, text: String? = nil, previewText: String?? = nil,
        openTracking: Bool? = nil, clickTracking: Bool? = nil,
        data: [String: JSONValue]?? = nil, dataSource: BroadcastDataSourceInput?? = nil, recurrence: BroadcastRecurrence?? = nil
    ) {
        self.name = name
        self.segmentId = segmentId
        self.topicId = topicId
        self.from = from
        self.subject = subject
        self.replyTo = replyTo
        self.html = html
        self.text = text
        self.previewText = previewText
        self.openTracking = openTracking
        self.clickTracking = clickTracking
        self.data = data
        self.dataSource = dataSource
        self.recurrence = recurrence
    }

    enum CodingKeys: String, CodingKey {
        case name, from, subject, html, text
        case segmentId = "segment_id"
        case topicId = "topic_id"
        case replyTo = "reply_to"
        case previewText = "preview_text"
        case openTracking = "open_tracking"
        case clickTracking = "click_tracking"
        case data, recurrence
        case dataSource = "data_source"
    }
}

public struct SendBroadcastInput: Encodable, Sendable {
    public var scheduledAt: String?
    /// Bu gönderimin `{{{data.*}}}` bağlamı (taslaktakinin yerine).
    public var data: [String: JSONValue]?

    public init(scheduledAt: String? = nil, data: [String: JSONValue]? = nil) {
        self.scheduledAt = scheduledAt
        self.data = data
    }

    enum CodingKeys: String, CodingKey {
        case data
        case scheduledAt = "scheduled_at"
    }
}
