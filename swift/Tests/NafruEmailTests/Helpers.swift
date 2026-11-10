import Foundation
@testable import NafruEmail

struct Reply: Sendable {
    var status = 200
    var headers: [String: String] = [:]
    var body = Data()

    static func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> Reply {
        Reply(status: status, headers: headers.merging(["Content-Type": "application/json"]) { a, _ in a },
              body: try! JSONSerialization.data(withJSONObject: object))
    }
}

struct Call: Sendable {
    let request: URLRequest
    var url: String { request.url!.absoluteString }
    var path: String { request.url!.path }
    var method: String { request.httpMethod ?? "" }
    var auth: String? { request.value(forHTTPHeaderField: "Authorization") }
    func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    var json: Any? { request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } }
}

/// Sahte sunucu: `route` her çağrı için yanıt verir (`index` 0'dan); çağrılar kaydedilir.
final class MockServer: NafruTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Call] = []
    private let route: @Sendable (Call, Int) async throws -> Reply

    init(_ route: @escaping @Sendable (Call, Int) async throws -> Reply) {
        self.route = route
    }

    /// Yanıtları sırayla verir, son yanıtı tekrarlar.
    convenience init(_ replies: [Reply]) {
        self.init { _, index in replies[min(index, replies.count - 1)] }
    }

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    private func record(_ call: Call) -> Int {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(call)
        return recorded.count - 1
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let call = Call(request: request)
        let index = record(call)
        let reply = try await route(call, index)
        return (reply.body, HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: reply.headers)!)
    }
}

func client(_ server: MockServer, maxRetries: Int = 0, timeout: TimeInterval = 30) throws -> NafruEmail {
    try NafruEmail("key_test", baseURL: "https://api.test/", transport: server, maxRetries: maxRetries, timeout: timeout, devOutbox: .disabled)
}

func jsonEqual(_ lhs: Any?, _ rhs: Any) -> Bool {
    guard let lhs else { return false }
    return (lhs as AnyObject).isEqual(rhs)
}
