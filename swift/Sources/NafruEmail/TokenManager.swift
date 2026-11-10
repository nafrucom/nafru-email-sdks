import Foundation

private struct TokenPayload: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

/// Bağlantının erişim belirtecini tutar ve yeniler. Eşzamanlı çağrılar TEK yenilemeyi paylaşır (tek uçuş): dönüşlü yenileme belirteci
/// ikinci bir eşzamanlı yenilemede "yeniden kullanım" sayılır ve bağlantıyı iptal ettirirdi.
actor TokenManager {
    /// Süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı).
    private static let earlyRefresh: TimeInterval = 30

    private let oauth: Requester
    private let clientId: String
    private let clientSecret: String
    private let onTokenRefresh: @Sendable (ConnectionTokens) async throws -> Void
    private var refreshToken: String
    private var accessToken: String?
    private var expiresAt = Date.distantPast
    private var inflight: Task<String, Error>?
    /// Yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı: eski belirteç artık geçersiz, bu kaybolmamalı.
    private var unpersisted = false
    /// En son verilen belirteç: 401 `invalid_token` gelince geçersiz sayılacak olan.
    private(set) var lastIssued: String?

    init(oauth: Requester, clientId: String, clientSecret: String, options: ConnectionOptions) {
        self.oauth = oauth
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.onTokenRefresh = options.onTokenRefresh
        self.refreshToken = options.refreshToken
    }

    /// Geçerli erişim belirteci; yoksa ya da dolmak üzereyse tek uçuşla yeniler.
    func token() async throws -> String {
        if unpersisted { try await persist() }
        if let accessToken, Date() < expiresAt.addingTimeInterval(-Self.earlyRefresh) {
            lastIssued = accessToken
            return accessToken
        }
        let token = try await refresh()
        lastIssued = token
        return token
    }

    /// Sunucu 401 `invalid_token` dedi: eldeki belirteci at ve yenile (aynı belirteçle eşzamanlı 401'ler tek yenilemeyi paylaşır).
    func invalidate(_ stale: String) async throws -> String {
        if accessToken == stale { accessToken = nil }
        if let accessToken { return accessToken }
        return try await refresh()
    }

    private func refresh() async throws -> String {
        if let inflight { return try await inflight.value }
        let task = Task { try await self.performRefresh() }
        inflight = task
        return try await task.value
    }

    private func performRefresh() async throws -> String {
        defer { inflight = nil }
        let payload: TokenPayload
        do {
            payload = try await oauth(.post("/oauth/token", [
                "grant_type": "refresh_token",
                "client_id": clientId,
                "client_secret": clientSecret,
                "refresh_token": refreshToken
            ]))
        } catch var error as NafruError {
            // Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi döner.
            if error.name == "invalid_grant" || error.name == "connection_revoked"
                || (error.statusCode == 403 && error.name != "rate_limit_exceeded") {
                error.name = "connection_revoked"
                error.message = "Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir."
            }
            throw error
        }
        refreshToken = payload.refreshToken
        accessToken = payload.accessToken
        expiresAt = Date().addingTimeInterval(payload.expiresIn)
        try await persist()
        return payload.accessToken
    }

    private func persist() async throws {
        do {
            try await onTokenRefresh(ConnectionTokens(refreshToken: refreshToken))
            unpersisted = false
        } catch {
            unpersisted = true
            throw NafruError(statusCode: nil, name: "token_persist_failed", message: "Yeni yenileme belirteci saklanamadı: \(error.localizedDescription)")
        }
    }
}
