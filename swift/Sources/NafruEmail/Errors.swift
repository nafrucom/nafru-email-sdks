import Foundation

public struct NafruFieldError: Equatable, Sendable {
    public var field: String
    public var message: String
    public var i18nTranslationKey: String?

    public init(field: String, message: String, i18nTranslationKey: String? = nil) {
        self.field = field
        self.message = message
        self.i18nTranslationKey = i18nTranslationKey
    }
}

/// Her başarısız çağrının fırlattığı hata. `statusCode` ağ hatalarında `nil`'dır. `name`, sunucunun hata adıdır
/// (`validation_error`, `rate_limit_exceeded`, `not_found`, …); ağ ve zaman aşımı için `application_error` / `timeout_error`.
public struct NafruError: Error, Equatable, Sendable, LocalizedError {
    public var statusCode: Int?
    public var name: String
    public var message: String
    public var errors: [NafruFieldError]?
    /// `429` yanıtındaki `retry-after` (saniye).
    public var retryAfter: Double?

    public init(statusCode: Int?, name: String, message: String, errors: [NafruFieldError]? = nil, retryAfter: Double? = nil) {
        self.statusCode = statusCode
        self.name = name
        self.message = message
        self.errors = errors
        self.retryAfter = retryAfter
    }

    public var errorDescription: String? { message }

    static func network(_ message: String) -> NafruError {
        NafruError(statusCode: nil, name: "application_error", message: message)
    }

    static func timeout(_ seconds: TimeInterval) -> NafruError {
        NafruError(statusCode: nil, name: "timeout_error", message: "İstek \(Int(seconds * 1000)) ms içinde tamamlanmadı")
    }
}

private let namesByStatus: [Int: String] = [
    400: "invalid_request",
    401: "unauthorized",
    403: "forbidden",
    404: "not_found",
    409: "conflict",
    413: "payload_too_large",
    422: "validation_error",
    429: "rate_limit_exceeded"
]

/// Standart gövde (`statusCode`, `name`, `message`, `errors`) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde).
func parseError(status: Int, retryAfterHeader: String?, body: Data) -> NafruError {
    let retryAfter = retryAfterHeader.flatMap { Double($0.trimmingCharacters(in: .whitespaces)) }.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
    let fallbackName = namesByStatus[status] ?? "application_error"
    guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
          let message = object["message"] as? String
    else {
        return NafruError(statusCode: status, name: fallbackName, message: "HTTP \(status)", retryAfter: retryAfter)
    }
    let errors = (object["errors"] as? [Any])?.compactMap { $0 as? [String: Any] }.map {
        NafruFieldError(
            field: $0["field"] as? String ?? "",
            message: $0["message"] as? String ?? "",
            i18nTranslationKey: $0["i18nTranslationKey"] as? String
        )
    }
    return NafruError(
        statusCode: object["statusCode"] as? Int ?? status,
        name: object["name"] as? String ?? fallbackName,
        message: message,
        errors: errors?.isEmpty == false ? errors : nil,
        retryAfter: retryAfter
    )
}
