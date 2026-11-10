import Foundation

/// İstekleri gönderen katman. Varsayılanı `URLSessionTransport`; testte ya da proxy için kendinizinkini verin.
/// Zaman aşımı görevi iptal eder: uygulamanız iptale (`Task.isCancelled`) uymalıdır.
public protocol NafruTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: NafruTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Yönlendirme izlenmez: başka bir sunucuya `Authorization` sızdırabilir; 3xx yanıtı olduğu gibi döner.
        let (data, response) = try await session.data(for: request, delegate: NoRedirectDelegate.shared)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// API asla yönlendirmez; yönlendirmeyi reddeder.
final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = NoRedirectDelegate()

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Liste sorguları: boş ya da `nil` değerler gönderilmez.
public protocol NafruQuery: Sendable {
    var queryItems: [URLQueryItem] { get }
}

/// `after` imleciyle sayfalanabilen sorgu.
public protocol PageableQuery: NafruQuery {
    var after: String? { get set }
}

func nonEmptyQueryItems(_ pairs: [(String, String?)]) -> [URLQueryItem] {
    pairs.compactMap { key, value in
        guard let value, !value.isEmpty else { return nil }
        return URLQueryItem(name: key, value: value)
    }
}

// `encodeURIComponent` ile aynı küme: kişi uçları e-postayı (`a+b@x`) kimlik gibi kabul eder.
private let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")

func percentEncode(_ value: String) -> String {
    value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
}

/// Yol parçası (kimlik, e-posta, takma ad, dil) güvenle kaçırılır. Boş, `.` ve `..` reddedilir: adres çözümlemesinde
/// sadeleşip başka bir uca giderlerdi.
func seg(_ value: String) throws -> String {
    guard !value.isEmpty, value != ".", value != ".." else {
        throw NafruError(statusCode: nil, name: "invalid_argument", message: "Geçersiz yol parçası: boş, '.' ya da '..' olamaz")
    }
    return percentEncode(value)
}

func formEncode(_ items: [URLQueryItem]) -> String {
    items.map { "\(percentEncode($0.name))=\(percentEncode($0.value ?? ""))" }.joined(separator: "&")
}

/// Yalnız https; http yalnız yerel geliştirme adreslerinde (`localhost`, `*.localhost`, `127.0.0.0/8`, `[::1]`).
func requireSecureURL(_ value: String, name: String) throws {
    let components = URLComponents(string: value)
    let scheme = components?.scheme?.lowercased()
    let host = (components?.host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    let loopback = host == "localhost" || host.hasSuffix(".localhost") || host == "::1"
        || (host.hasPrefix("127.") && host.split(separator: ".").count == 4 && host.split(separator: ".").allSatisfy { UInt8($0) != nil })
    guard scheme == "https" || (scheme == "http" && loopback), !host.isEmpty else {
        throw NafruError(statusCode: nil, name: "invalid_argument", message: "\(name) https kullanmalı (http yalnız localhost için)")
    }
}

/// Gövde sınırı: bozuk ya da kötü niyetli bir ara sunucu belleği tüketemesin.
let maxResponseBytes = 10 * 1024 * 1024

func trimTrailingSlashes(_ value: String) -> String {
    var value = value
    while value.hasSuffix("/") { value.removeLast() }
    return value
}

struct Request: Sendable {
    var method: String
    var path: String
    var query: [URLQueryItem] = []
    var body: (any Encodable & Sendable)?
    /// `Idempotency-Key` başlığı (olay uçları tekrarı yok sayar).
    var idempotencyKey: String?

    static func get(_ path: String, _ query: (any NafruQuery)? = nil) -> Request {
        Request(method: "GET", path: path, query: query?.queryItems ?? [])
    }

    static func post(_ path: String, _ body: (any Encodable & Sendable)? = nil, idempotencyKey: String? = nil) -> Request {
        Request(method: "POST", path: path, body: body, idempotencyKey: idempotencyKey)
    }

    static func patch(_ path: String, _ body: any Encodable & Sendable) -> Request {
        Request(method: "PATCH", path: path, body: body)
    }

    static func put(_ path: String, _ body: any Encodable & Sendable) -> Request {
        Request(method: "PUT", path: path, body: body)
    }

    static func delete(_ path: String) -> Request {
        Request(method: "DELETE", path: path)
    }
}

enum Authorization: Sendable {
    case none
    case bearer(String)
    /// Her denemede belirteç buradan alınır; hata istek göndermeden fırlar.
    case dynamic(@Sendable () async throws -> String)
}

/// Kullanımdan kaldırma uyarısını istemci başına bir kez basar (`Deprecation` yanıt başlığı).
final class DeprecationNotice: @unchecked Sendable {
    private let lock = NSLock()
    private var warned = false
    private let output: @Sendable (String) -> Void

    init(output: @escaping @Sendable (String) -> Void = { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }) {
        self.output = output
    }

    func check(_ response: HTTPURLResponse) {
        guard response.value(forHTTPHeaderField: "Deprecation") != nil else { return }
        lock.lock()
        let first = !warned
        warned = true
        lock.unlock()
        guard first else { return }
        var message = "[nafru] Bu SDK sürümü (swift \(NafruSDK.version)) kullanımdan kaldırıldı; lütfen güncelleyin."
        if let sunset = response.value(forHTTPHeaderField: "Sunset") { message += " Son tarih: \(sunset)" }
        if let link = response.value(forHTTPHeaderField: "Link") {
            let url = link.firstIndex(of: "<").flatMap { start in
                link[start...].firstIndex(of: ">").map { String(link[link.index(after: start)..<$0]) }
            }
            message += " Ayrıntı: \(url ?? link)"
        }
        output(message)
    }
}

private struct TimeoutSignal: Error {}

private func withTimeout<T: Sendable>(_ seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutSignal()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}

private func sleep(seconds: Double) async {
    try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
}

struct HTTPClient: Sendable {
    let baseURL: String
    let auth: Authorization
    let transport: any NafruTransport
    let maxRetries: Int
    let timeout: TimeInterval
    let deprecation: DeprecationNotice

    init(baseURL: String, auth: Authorization, transport: any NafruTransport, maxRetries: Int, timeout: TimeInterval, deprecation: DeprecationNotice) {
        self.baseURL = trimTrailingSlashes(baseURL)
        self.auth = auth
        self.transport = transport
        self.maxRetries = maxRetries
        self.timeout = timeout
        self.deprecation = deprecation
    }

    var requester: Requester { Requester { try await perform($0) } }

    /// `GET` ve `DELETE` yinelenebilir; `POST`/`PATCH` yalnız istek işlenmeden reddedildiyse (429) ya da `Idempotency-Key`
    /// taşıyorsa yinelenir: anahtarsız sunucu hatasında e-posta çift gidebilir.
    func perform(_ input: Request) async throws -> Data {
        let query = input.query.isEmpty ? "" : "?" + formEncode(input.query)
        guard let url = URL(string: baseURL + input.path + query) else {
            throw NafruError.network("Geçersiz adres: \(baseURL + input.path)")
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = input.method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("nafru-email-swift/\(NafruSDK.version)", forHTTPHeaderField: "User-Agent")
        if case .bearer(let key) = auth { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        if let body = input.body {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw NafruError.network("İstek gövdesi kodlanamadı: \(error)")
            }
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let key = input.idempotencyKey {
            // Başlık enjeksiyonu: CR/LF ve diğer denetim karakterleri reddedilir.
            guard !key.isEmpty, !key.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                throw NafruError(statusCode: nil, name: "invalid_argument", message: "Geçersiz idempotencyKey: boş olamaz, denetim karakteri içeremez")
            }
            request.setValue(key, forHTTPHeaderField: "Idempotency-Key")
        }
        let safeToRetry = input.method == "GET" || input.method == "DELETE" || input.idempotencyKey != nil

        var attempt = 0
        while true {
            if case .dynamic(let token) = auth {
                request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
            }
            let last = attempt >= maxRetries
            let backoff = min(0.3 * pow(2, Double(attempt)), 8)
            attempt += 1

            let data: Data
            let response: HTTPURLResponse
            do {
                let sent = request
                (data, response) = try await withTimeout(timeout) { [transport] in try await transport.send(sent) }
            } catch {
                if Task.isCancelled { throw NafruError.network("İstek iptal edildi") }
                let timedOut = error is TimeoutSignal || (error as? URLError)?.code == .timedOut
                if !last && safeToRetry {
                    await sleep(seconds: backoff)
                    continue
                }
                throw timedOut ? NafruError.timeout(timeout) : NafruError.network(error.localizedDescription)
            }

            deprecation.check(response)
            // shortcut: sınır gövde okunduktan sonra denetlenir (URLSession.data tümünü belleğe alır); akışla okuma gerekirse bytes(for:) ile kesilir.
            if data.count > maxResponseBytes {
                throw NafruError(statusCode: response.statusCode, name: "response_too_large", message: "Yanıt gövdesi 10 MB sınırını aşıyor")
            }
            if (300..<400).contains(response.statusCode) {
                throw NafruError(statusCode: response.statusCode, name: "unexpected_redirect",
                                 message: "Beklenmeyen yönlendirme (HTTP \(response.statusCode)); kimlik bilgisi sızmasın diye izlenmedi")
            }
            if (200..<300).contains(response.statusCode) { return data }

            let error = parseError(status: response.statusCode, retryAfterHeader: response.value(forHTTPHeaderField: "Retry-After"), body: data)
            let retryable = response.statusCode == 429 || (response.statusCode >= 500 && safeToRetry)
            if retryable && !last {
                await sleep(seconds: min(error.retryAfter ?? backoff, 8))
                continue
            }
            throw error
        }
    }
}

/// Kaynakların kullandığı istek işlevi; bağlantı istemcisi bunu `invalid_token` yeniden denemesiyle sarar.
struct Requester: Sendable {
    let perform: @Sendable (Request) async throws -> Data

    func callAsFunction<T: Decodable>(_ input: Request, as type: T.Type = T.self) async throws -> T {
        let data = try await perform(input)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NafruError.network("Yanıt çözümlenemedi: \(error)")
        }
    }
}
