import Foundation

public struct Attachment: Encodable, Sendable {
    /// Base64 metni. `path` ile birlikte verilmez.
    public var content: String?
    /// Herkese açık https adresi. `content` ile birlikte verilmez.
    public var path: String?
    public var filename: String?
    public var contentType: String?
    public var contentId: String?

    public init(content: String? = nil, path: String? = nil, filename: String? = nil, contentType: String? = nil, contentId: String? = nil) {
        self.content = content
        self.path = path
        self.filename = filename
        self.contentType = contentType
        self.contentId = contentId
    }

    enum CodingKeys: String, CodingKey {
        case content, path, filename
        case contentType = "content_type"
        case contentId = "content_id"
    }
}

/// Şablonla gönderim: kimlik ya da takma ad ve değişken değerleri.
public struct EmailTemplate: Encodable, Sendable {
    public var id: String
    public var variables: [String: JSONValue]?

    public init(id: String, variables: [String: JSONValue]? = nil) {
        self.id = id
        self.variables = variables
    }
}

public struct SendEmailInput: Encodable, Sendable {
    /// `Ad <adres@alan.com>` ya da adres. Şablonla gönderimde isteğe bağlıdır (çalışma alanı varsayılanı).
    public var from: String?
    public var to: [String]
    public var cc: [String]?
    public var bcc: [String]?
    public var replyTo: [String]?
    public var subject: String?
    public var headers: [String: String]?
    public var tags: [Tag]?
    /// ISO 8601 ya da göreli ifade (`in 1 hour`). Geçmiş an hemen gönderir; en fazla 30 gün sonrası.
    public var scheduledAt: String?
    public var html: String?
    public var text: String?
    public var attachments: [Attachment]?
    /// Şablonla gönderim: `html`/`text`/`attachments` ile birlikte verilmez.
    public var template: EmailTemplate?

    public init(
        from: String? = nil, to: [String], cc: [String]? = nil, bcc: [String]? = nil, replyTo: [String]? = nil,
        subject: String? = nil, headers: [String: String]? = nil, tags: [Tag]? = nil, scheduledAt: String? = nil,
        html: String? = nil, text: String? = nil, attachments: [Attachment]? = nil, template: EmailTemplate? = nil
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.subject = subject
        self.headers = headers
        self.tags = tags
        self.scheduledAt = scheduledAt
        self.html = html
        self.text = text
        self.attachments = attachments
        self.template = template
    }

    enum CodingKeys: String, CodingKey {
        case from, to, cc, bcc, subject, headers, tags, html, text, attachments, template
        case replyTo = "reply_to"
        case scheduledAt = "scheduled_at"
    }
}

/// Toplu öğe: ek ve şablon desteklenmez.
public struct BatchEmailItem: Encodable, Sendable {
    public var from: String
    public var to: [String]
    public var cc: [String]?
    public var bcc: [String]?
    public var replyTo: [String]?
    public var subject: String
    public var headers: [String: String]?
    public var tags: [Tag]?
    public var scheduledAt: String?
    public var html: String?
    public var text: String?

    public init(
        from: String, to: [String], cc: [String]? = nil, bcc: [String]? = nil, replyTo: [String]? = nil, subject: String,
        headers: [String: String]? = nil, tags: [Tag]? = nil, scheduledAt: String? = nil, html: String? = nil, text: String? = nil
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.replyTo = replyTo
        self.subject = subject
        self.headers = headers
        self.tags = tags
        self.scheduledAt = scheduledAt
        self.html = html
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case from, to, cc, bcc, subject, headers, tags, html, text
        case replyTo = "reply_to"
        case scheduledAt = "scheduled_at"
    }

    var asSendInput: SendEmailInput {
        SendEmailInput(
            from: from, to: to, cc: cc, bcc: bcc, replyTo: replyTo, subject: subject, headers: headers, tags: tags,
            scheduledAt: scheduledAt, html: html, text: text
        )
    }
}

public struct SendEmailResponse: Decodable, Sendable, Identifiable {
    public let id: String
}

public struct BatchEmailResponse: Decodable, Sendable {
    public let data: [SendEmailResponse]
}

public struct EmailListItem: Decodable, Sendable, Identifiable {
    public let id: String
    public let to: [String]
    public let from: String
    public let createdAt: String
    public let subject: String
    public let bcc: [String]?
    public let cc: [String]?
    public let replyTo: [String]?
    /// `queued`, `sent`, `delivered`, `bounced`, … (yeni değerler gelebilir).
    public let lastEvent: String
    public let scheduledAt: String?
    public let messageId: String?

    enum CodingKeys: String, CodingKey {
        case id, to, from, subject, bcc, cc
        case createdAt = "created_at"
        case replyTo = "reply_to"
        case lastEvent = "last_event"
        case scheduledAt = "scheduled_at"
        case messageId = "message_id"
    }
}

public struct EmailEvent: Decodable, Sendable, Identifiable {
    public let id: String
    public let type: String
    public let createdAt: String
    public let detail: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case id, type, detail
        case createdAt = "created_at"
    }
}

public struct Email: Decodable, Sendable, Identifiable {
    public let object: String
    public let id: String
    public let to: [String]
    public let from: String
    public let createdAt: String
    public let subject: String
    public let bcc: [String]?
    public let cc: [String]?
    public let replyTo: [String]?
    public let lastEvent: String
    public let scheduledAt: String?
    public let messageId: String?
    public let html: String?
    public let text: String?
    public let tags: [Tag]
    public let events: [EmailEvent]

    enum CodingKeys: String, CodingKey {
        case object, id, to, from, subject, bcc, cc, html, text, tags, events
        case createdAt = "created_at"
        case replyTo = "reply_to"
        case lastEvent = "last_event"
        case scheduledAt = "scheduled_at"
        case messageId = "message_id"
    }
}

public struct ListEmailsQuery: PageableQuery {
    public var limit: Int?
    public var after: String?
    public var before: String?
    public var status: String?

    public init(limit: Int? = nil, after: String? = nil, before: String? = nil, status: String? = nil) {
        self.limit = limit
        self.after = after
        self.before = before
        self.status = status
    }

    public var queryItems: [URLQueryItem] {
        nonEmptyQueryItems([("limit", limit.map(String.init)), ("after", after), ("before", before), ("status", status)])
    }
}
