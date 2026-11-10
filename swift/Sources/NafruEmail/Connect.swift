import CryptoKit
import Foundation

private func base64URL(_ data: Data) -> String {
    data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

/// PKCE (S256): 32 rastgele bayttan 43 karakterlik doğrulayıcı ve SHA-256 sınaması.
func createPkce() -> (verifier: String, challenge: String) {
    var generator = SystemRandomNumberGenerator() // işletim sisteminin kriptografik üreteci
    let verifier = base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }))
    return (verifier, base64URL(Data(SHA256.hash(data: Data(verifier.utf8)))))
}

private struct GrantPayload: Decodable {
    let refreshToken: String
    let connectionId: String
    let scopes: [AppScope]

    enum CodingKeys: String, CodingKey {
        case scopes
        case refreshToken = "refresh_token"
        case connectionId = "connection_id"
    }
}

// "Nafru ile bağlan" akışı: izin adresi, kod değişimi ve iptal. Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
extension NafruConnect {
    /// Müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresi. `codeVerifier`'ı oturumda saklayın; dönüşte `exchange`'e verin.
    /// Dönüşte `state`'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur.
    /// - Parameters:
    ///   - redirectUri: Kayıtlı yönlendirme adresiyle birebir aynı olmalı.
    ///   - state: CSRF koruması: istekten önce üretip oturumda saklayın. Zorunlu.
    ///   - loginHint: Müşterinin e-postası biliniyorsa kayıt/giriş ekranında önerilir.
    public func authorizeUrl(redirectUri: String, state: String, scopes: [AppScope], loginHint: String? = nil) throws -> AuthorizeUrl {
        guard !state.isEmpty else { throw NafruError.network("Nafru SDK: state gerekli (CSRF koruması)") }
        guard !scopes.isEmpty else { throw NafruError.network("Nafru SDK: en az bir izin (scopes) gerekli") }
        let pkce = createPkce()
        let items = nonEmptyQueryItems([
            ("client_id", clientId),
            ("redirect_uri", redirectUri),
            ("state", state),
            ("scope", scopes.map(\.rawValue).joined(separator: " ")),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"),
            ("login_hint", loginHint)
        ])
        return AuthorizeUrl(url: "\(webURL)/connect?\(formEncode(items))", codeVerifier: pkce.verifier)
    }

    /// Dönüşteki tek kullanımlık `code`'u bağlantıya çevirir (sunucunuzdan çağırın).
    public func exchange(code: String, codeVerifier: String, redirectUri: String) async throws -> ConnectionGrant {
        let payload: GrantPayload = try await oauth(.post("/oauth/token", [
            "grant_type": "authorization_code",
            "client_id": clientId,
            "client_secret": clientSecret,
            "code": code,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectUri
        ]))
        return ConnectionGrant(connectionId: payload.connectionId, refreshToken: payload.refreshToken, scopes: payload.scopes)
    }

    /// Bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur.
    public func revoke(refreshToken: String) async throws {
        _ = try await oauth.perform(.post("/oauth/revoke", ["client_id": clientId, "client_secret": clientSecret, "token": refreshToken]))
    }
}
