import CryptoKit
import Foundation

// Svix / Standard Webhooks uyumlu imza doğrulama.
//   imzalanan = "<svix-id>.<svix-timestamp>.<ham gövde>"
//   anahtar   = `whsec_` sonrası base64 çözülmüş `signing_secret`
//   başlık    = `v1,<base64 HMAC-SHA256>` (anahtar döndürmede boşlukla ayrılmış birden çok imza)

public struct WebhookHeaders: Sendable {
    /// `svix-id`
    public var id: String
    /// `svix-timestamp`
    public var timestamp: String
    /// `svix-signature`
    public var signature: String

    public init(id: String, timestamp: String, signature: String) {
        self.id = id
        self.timestamp = timestamp
        self.signature = signature
    }
}

/// İmza ve zaman damgası geçerliyse `true`. Bozuk imza ya da zaman damgası `false`; bozuk `secret` hata fırlatır (yapılandırma hatası).
/// - Parameters:
///   - payload: HAM istek gövdesi: ayrıştırılıp yeniden dizilmiş JSON imzayı bozar.
///   - secret: Webhook'un `signing_secret` değeri (`whsec_…`).
///   - toleranceSeconds: Tekrar saldırısına karşı izin verilen zaman farkı; varsayılan 300.
///   - now: Şimdiki zaman; testler için.
public func verifyWebhook(payload: String, headers: WebhookHeaders, secret: String, toleranceSeconds: TimeInterval = 300, now: Date = Date()) throws -> Bool {
    try verifyWebhook(payload: Data(payload.utf8), headers: headers, secret: secret, toleranceSeconds: toleranceSeconds, now: now)
}

/// Ham gövde baytlarıyla doğrulama (çerçeve gövdeyi `Data` olarak veriyorsa bunu kullanın; metne çevirip geri dizmeyin).
public func verifyWebhook(payload: Data, headers: WebhookHeaders, secret: String, toleranceSeconds: TimeInterval = 300, now: Date = Date()) throws -> Bool {
    let prefix = "whsec_"
    guard secret.hasPrefix(prefix) else {
        throw NafruError.network("Geçersiz imza anahtarı: whsec_ ile başlamalı")
    }
    guard let raw = Data(base64Encoded: String(secret.dropFirst(prefix.count))) else {
        throw NafruError.network("Geçersiz imza anahtarı: base64 çözülemedi")
    }

    // Eksik/boş başlık: geçersiz imza (çökme yok). Zaman farkı iki yönde de sınırlı.
    guard !headers.id.isEmpty, !headers.signature.isEmpty,
          let timestamp = Double(headers.timestamp), timestamp.isFinite,
          abs(now.timeIntervalSince1970.rounded(.down) - timestamp) <= toleranceSeconds
    else { return false }

    let key = SymmetricKey(data: raw)
    let content = Data("\(headers.id).\(headers.timestamp).".utf8) + payload
    // Aşırı uzun başlık işlem tüketmesin: ilk 32 imza.
    for candidate in headers.signature.split(separator: " ").prefix(32) {
        let parts = candidate.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count >= 2, parts[0] == "v1", let mac = Data(base64Encoded: String(parts[1])) else { continue }
        // `isValidAuthenticationCode` sabit zamanlı karşılaştırır.
        if HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: content, using: key) { return true }
    }
    return false
}
