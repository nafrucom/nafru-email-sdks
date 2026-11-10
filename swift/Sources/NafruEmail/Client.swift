import Foundation

/// `nil` ya da boş: üretim API'si.
func effectiveBaseURL(_ baseURL: String?) -> String {
    guard let baseURL, !baseURL.isEmpty else { return NafruSDK.defaultBaseURL }
    return baseURL
}

/// API anahtarlı istemci (Resend'deki `Resend('re_…')` gibi): `try NafruEmail("nafru_…")`. Hatalar `NafruError` olarak fırlatılır.
public struct NafruEmail: Sendable {
    public let emails: Emails
    public let domains: Domains
    public let contacts: Contacts
    public let contactProperties: ContactProperties
    public let segments: Segments
    public let topics: Topics
    public let broadcasts: Broadcasts
    public let templates: Templates
    public let brand: BrandResource
    public let webhooks: Webhooks
    public let apiKeys: ApiKeys
    public let events: Events

    /// - Parameters:
    ///   - apiKey: Dashboard'dan üretilen API anahtarı; verilmezse ya da boşsa `NAFRU_API_KEY` ortam değişkeni. Uygulama paketine
    ///     gömmeyin; `sending_access` anahtarı bile e-posta gönderebilir.
    ///   - baseURL: API'nin kök adresi; varsayılan `NafruSDK.defaultBaseURL` (yerelde `http://localhost:48787/api`).
    ///   - transport: Özel taşıma katmanı (test, proxy).
    ///   - maxRetries: `429` ve güvenli isteklerde sunucu/ağ hatası için yeniden deneme sayısı; `0` kapatır.
    ///   - timeout: İstek başına zaman aşımı (saniye).
    ///   - devOutbox: Verilmezse `NODE_ENV=development` iken `.nafru/emails`, aksi hâlde kapalı; `.disabled` her zaman gerçek gönderim.
    public init(
        _ apiKey: String? = nil, baseURL: String? = nil, transport: any NafruTransport = URLSessionTransport(), maxRetries: Int = 2,
        timeout: TimeInterval = 30, devOutbox: DevOutbox? = nil
    ) throws {
        try self.init(apiKey, baseURL: baseURL, transport: transport, maxRetries: maxRetries, timeout: timeout,
                      devOutbox: devOutbox, deprecation: DeprecationNotice())
    }

    init(
        _ apiKey: String?, baseURL: String?, transport: any NafruTransport, maxRetries: Int, timeout: TimeInterval,
        devOutbox: DevOutbox?, deprecation: DeprecationNotice, environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 } ?? environment["NAFRU_API_KEY"] ?? ""
        guard !apiKey.isEmpty else { throw NafruError.network("Nafru SDK: apiKey gerekli") }
        let base = effectiveBaseURL(baseURL)
        try requireSecureURL(base, name: "baseUrl")
        let http = HTTPClient(baseURL: base, auth: .bearer(apiKey), transport: transport, maxRetries: maxRetries,
                              timeout: timeout, deprecation: deprecation).requester
        emails = Emails(http: http, devOutbox: resolveDevOutbox(devOutbox))
        domains = Domains(http: http)
        contacts = Contacts(http: http)
        contactProperties = ContactProperties(http: http)
        segments = Segments(http: http)
        topics = Topics(http: http)
        broadcasts = Broadcasts(http: http)
        templates = Templates(http: http)
        brand = BrandResource(http: http)
        webhooks = Webhooks(http: http)
        apiKeys = ApiKeys(http: http)
        events = Events(http: http)
    }
}

/// "Nafru ile bağlan" istemcisi: müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına gönderir.
/// `authorizeUrl`, `exchange`, `revoke` ve `connection` doğrudan bunun üzerindedir. Tek alan adı/anahtar için `NafruEmail("nafru_…")` kullanın.
public struct NafruConnect: Sendable {
    private let makeHTTP: @Sendable (Authorization) -> HTTPClient
    let oauth: Requester
    let clientId: String
    let clientSecret: String
    let webURL: String
    private let devOutbox: String?

    /// - Parameters:
    ///   - clientId: Kayıtlı uygulamanın `app_…` kimliği.
    ///   - clientSecret: Yalnız sunucunuzda; istemci uygulamasına girmez.
    ///   - baseURL: API'nin kök adresi; varsayılan `NafruSDK.defaultBaseURL`.
    ///   - webURL: İzin ekranının kök adresi; verilmezse `baseURL` sonundaki `/api` atılır.
    public init(
        clientId: String, clientSecret: String, baseURL: String? = nil, webURL: String? = nil,
        transport: any NafruTransport = URLSessionTransport(), maxRetries: Int = 2, timeout: TimeInterval = 30, devOutbox: DevOutbox? = nil
    ) throws {
        try self.init(clientId: clientId, clientSecret: clientSecret, baseURL: baseURL, webURL: webURL, transport: transport,
                      maxRetries: maxRetries, timeout: timeout, devOutbox: devOutbox, deprecation: DeprecationNotice())
    }

    init(
        clientId: String, clientSecret: String, baseURL: String?, webURL: String?, transport: any NafruTransport,
        maxRetries: Int, timeout: TimeInterval, devOutbox: DevOutbox?, deprecation: DeprecationNotice
    ) throws {
        guard !clientId.isEmpty else { throw NafruError.network("Nafru SDK: clientId gerekli") }
        guard !clientSecret.isEmpty else { throw NafruError.network("Nafru SDK: clientSecret gerekli") }
        let base = effectiveBaseURL(baseURL)
        try requireSecureURL(base, name: "baseUrl")
        let makeHTTP: @Sendable (Authorization) -> HTTPClient = {
            HTTPClient(baseURL: base, auth: $0, transport: transport, maxRetries: maxRetries, timeout: timeout, deprecation: deprecation)
        }
        // Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
        let oauth = makeHTTP(.none).requester
        let web = webURL ?? base.replacingOccurrences(of: "/api/*$", with: "", options: .regularExpression)
        try requireSecureURL(web, name: "webUrl")
        self.makeHTTP = makeHTTP
        self.oauth = oauth
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.devOutbox = resolveDevOutbox(devOutbox)
        self.webURL = trimTrailingSlashes(web)
    }

    /// Saklanan yenileme belirteciyle bir müşteri bağlantısı. Yenileme otomatiktir; yeni belirteç `onTokenRefresh` ile gelir.
    public func connection(_ connectionId: String, _ options: ConnectionOptions) -> NafruConnection {
        let tokens = TokenManager(oauth: oauth, clientId: clientId, clientSecret: clientSecret, options: options)
        let http = makeHTTP(.dynamic { try await tokens.token() })
        // 401 `invalid_token` (süre dolmuş / yenilenmiş): bir kez yenileyip tekrar dener.
        let call = Requester { input in
            do {
                return try await http.perform(input)
            } catch let error as NafruError where error.name == "invalid_token" {
                guard let stale = await tokens.lastIssued else { throw error }
                _ = try await tokens.invalidate(stale)
                return try await http.perform(input)
            }
        }
        return NafruConnection(id: connectionId, call: call, devOutbox: devOutbox)
    }
}

/// Bir müşteri bağlantısı adına çağrılar. Yönetim uçları (anahtar, domain, kişi, kampanya) bağlantı belirteciyle çağrılamaz.
public struct NafruConnection: Sendable {
    public let id: String
    public let senders: Senders
    /// Müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe.
    public let templates: Templates
    public let emails: Emails
    let call: Requester

    init(id: String, call: Requester, devOutbox: String?) {
        self.id = id
        self.call = call
        senders = Senders(call: call)
        templates = Templates(call: call)
        emails = Emails(inner: EmailsResource(http: call, devOutbox: devOutbox))
    }

    /// `GET /connection`: hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi.
    public func status() async throws -> ConnectionStatus {
        try await call(.get("/connection"))
    }

    public struct Senders: Sendable {
        let call: Requester
        public func list() async throws -> ConnectionSenders { try await call(.get("/senders")) }
    }

    public struct Templates: Sendable {
        let call: Requester
        public func list() async throws -> ListResponse<ConnectionTemplate> { try await call(.get("/templates")) }
    }

    public struct Emails: Sendable {
        let inner: EmailsResource
        public func send(_ input: SendEmailInput, idempotencyKey: String? = nil) async throws -> SendEmailResponse {
            try await inner.send(input, idempotencyKey: idempotencyKey)
        }
        public func get(_ id: String) async throws -> Email { try await inner.get(id) }
        public func list(_ query: ListEmailsQuery = .init()) async throws -> ListResponse<EmailListItem> { try await inner.list(query) }
    }
}
