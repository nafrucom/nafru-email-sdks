import Foundation

/// Gizli değer (`nafru_…`, `nfr_…`, `whsec_…`) yazdırılırken yalnız ön eki görünür: `nafru_****`.
func redacted(_ secret: String) -> String {
    guard let underscore = secret.firstIndex(of: "_"), secret.distance(from: secret.startIndex, to: underscore) <= 8 else { return "[REDACTED]" }
    return secret[...underscore] + "****"
}

/// `print`, `"\(x)"`, `debugPrint` ve `dump` gizli alanları göstermez; yalnız `redactedFields` görünür.
protocol RedactedDescription: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var redactedFields: KeyValuePairs<String, Any> { get }
}

extension RedactedDescription {
    public var description: String {
        "\(Self.self)(" + redactedFields.map { "\($0.key): \($0.value)" }.joined(separator: ", ") + ")"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: redactedFields.map { (label: Optional($0.key), value: $0.value) }, displayStyle: .struct)
    }
}

extension NafruEmail: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["apiKey": "[REDACTED]"] }
}

extension NafruConnect: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> {
        ["clientId": clientId, "clientSecret": redacted(clientSecret), "webURL": webURL]
    }
}

extension NafruConnection: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["id": id] }
}

extension ConnectionGrant: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> {
        ["connectionId": connectionId, "refreshToken": redacted(refreshToken), "scopes": scopes.map(\.rawValue)]
    }
}

extension ConnectionTokens: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["refreshToken": redacted(refreshToken)] }
}

extension ConnectionOptions: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["refreshToken": redacted(refreshToken)] }
}

extension AuthorizeUrl: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["url": url, "codeVerifier": "[REDACTED]"] }
}

extension CreatedApiKey: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["id": id, "token": redacted(token)] }
}

extension CreatedWebhook: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["object": object, "id": id, "signingSecret": redacted(signingSecret)] }
}

extension WebhookDetail: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> {
        ["id": id, "endpoint": endpoint, "status": status, "events": events.map(\.rawValue), "signingSecret": redacted(signingSecret)]
    }
}

// İç tipler kapanışlarda tutulur ama doğrudan yazdırılırsa da sızmasın.
extension HTTPClient: RedactedDescription {
    var redactedFields: KeyValuePairs<String, Any> { ["baseURL": baseURL] }
}

extension TokenManager: CustomStringConvertible, CustomReflectable {
    nonisolated var description: String { "TokenManager([REDACTED])" }
    nonisolated var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }
}
