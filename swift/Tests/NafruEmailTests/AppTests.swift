import CryptoKit
import Foundation
import XCTest
@testable import NafruEmail

private func tokenJSON(_ n: Int) -> [String: Any] {
    ["access_token": "nfa_\(n)", "refresh_token": "nfr_\(n)", "token_type": "Bearer", "expires_in": 3600,
     "connection_id": "conn_1", "scopes": ["emails.send"]]
}

private let statusJSON: [String: Any] = [
    "object": "connection", "id": "conn_1", "ready": true, "missing": [], "hints": [], "scopes": ["emails.send"],
    "billing_mode": "customer_pays", "setup_url": "https://web.test/setup", "workspace": ["name": "Acme"]
]

private let grantError = Reply.json(["statusCode": 400, "name": "invalid_grant", "message": "invalid"], status: 400)

private func app(_ server: MockServer) throws -> NafruConnect {
    try NafruConnect(clientId: "app_x", clientSecret: "nfs_secret", baseURL: "https://api.test/", webURL: "https://web.test",
                 transport: server, maxRetries: 0, devOutbox: .disabled)
}

private func isToken(_ call: Call) -> Bool { call.path == "/oauth/token" }

final class Saved: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String] = []
    var failures = 0
    func save(_ value: String) throws {
        lock.lock()
        defer { lock.unlock() }
        if failures > 0 {
            failures -= 1
            throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk dolu"])
        }
        values.append(value)
    }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return values }
}

final class AppTests: XCTestCase {
    private func open(_ server: MockServer, saved: Saved = Saved()) throws -> NafruConnection {
        try app(server).connection("conn_1", ConnectionOptions(refreshToken: "nfr_0") { try saved.save($0.refreshToken) })
    }

    func testPkce() {
        let (verifier, challenge) = createPkce()
        XCTAssertNotNil(verifier.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
        let digest = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(challenge, digest)
        XCTAssertNotEqual(createPkce().verifier, verifier)
    }

    func testAuthorizeUrl() throws {
        let connect = try app(MockServer([.json([:])]))
        let result = try connect.authorizeUrl(redirectUri: "https://scout.test/cb", state: "st1", scopes: [.emailsSend, .templatesRead], loginHint: "a+b@c.co")
        let components = URLComponents(string: result.url)!
        XCTAssertEqual("\(components.scheme!)://\(components.host!)\(components.path)", "https://web.test/connect")
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["client_id"], "app_x")
        XCTAssertEqual(query["redirect_uri"], "https://scout.test/cb")
        XCTAssertEqual(query["state"], "st1")
        XCTAssertEqual(query["scope"], "emails.send templates.read")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["login_hint"], "a+b@c.co")
        XCTAssertTrue(result.url.contains("login_hint=a%2Bb%40c.co"))
        XCTAssertNotNil(query["code_challenge"]!.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
        XCTAssertNotNil(result.codeVerifier.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression))
        XCTAssertThrowsError(try connect.authorizeUrl(redirectUri: "x", state: "", scopes: [.emailsSend]))
        XCTAssertThrowsError(try connect.authorizeUrl(redirectUri: "x", state: "s", scopes: []))
    }

    func testWebURLDefaultsToBaseWithoutApi() throws {
        let nafru = try NafruConnect(clientId: "a", clientSecret: "s", baseURL: "https://email.nafru.com/api/", transport: MockServer([.json([:])]))
        XCTAssertTrue(try nafru.authorizeUrl(redirectUri: "r", state: "s", scopes: [.emailsSend]).url.hasPrefix("https://email.nafru.com/connect?"))
    }

    func testExchangeSendsCredentialsInBodyWithoutAuthorization() async throws {
        let server = MockServer([.json(tokenJSON(1))])
        let grant = try await app(server).exchange(code: "nfc_1", codeVerifier: String(repeating: "v", count: 43), redirectUri: "https://scout.test/cb")
        XCTAssertEqual(grant, ConnectionGrant(connectionId: "conn_1", refreshToken: "nfr_1", scopes: [.emailsSend]))
        let call = server.calls[0]
        XCTAssertEqual(call.url, "https://api.test/oauth/token")
        XCTAssertNil(call.auth)
        let body = call.json as! [String: String]
        XCTAssertEqual(body["grant_type"], "authorization_code")
        XCTAssertEqual(body["client_id"], "app_x")
        XCTAssertEqual(body["client_secret"], "nfs_secret")
        XCTAssertEqual(body["code"], "nfc_1")
    }

    func testExchangeErrorAndRevoke() async throws {
        await assertError(try await app(MockServer([grantError])).exchange(code: "c", codeVerifier: "v", redirectUri: "r"),
                          statusCode: 400, name: "invalid_grant")
        let server = MockServer([.json([:])])
        try await app(server).revoke(refreshToken: "nfr_1")
        XCTAssertTrue(jsonEqual(server.calls[0].json, ["client_id": "app_x", "client_secret": "nfs_secret", "token": "nfr_1"]))
    }

    func testFirstCallRefreshesAndPersists() async throws {
        let server = MockServer { call, _ in isToken(call) ? .json(tokenJSON(1)) : .json(statusJSON) }
        let saved = Saved()
        _ = try await open(server, saved: saved).status()
        XCTAssertEqual(saved.all, ["nfr_1"])
        XCTAssertEqual((server.calls[0].json as! [String: String])["refresh_token"], "nfr_0")
        XCTAssertEqual((server.calls[0].json as! [String: String])["grant_type"], "refresh_token")
        let api = server.calls.filter { !isToken($0) }
        XCTAssertEqual(api[0].url, "https://api.test/connection")
        XCTAssertEqual(api[0].auth, "Bearer nfa_1")
    }

    func testConcurrentCallsShareSingleRefresh() async throws {
        let server = MockServer { call, _ in
            if isToken(call) {
                try await Task.sleep(nanoseconds: 20_000_000)
                return .json(tokenJSON(1))
            }
            return .json(statusJSON)
        }
        let saved = Saved()
        let connection = try open(server, saved: saved)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 { group.addTask { _ = try await connection.status() } }
            try await group.waitForAll()
        }
        XCTAssertEqual(server.calls.filter(isToken).count, 1)
        XCTAssertEqual(saved.all, ["nfr_1"])
        _ = try await connection.status()
        XCTAssertEqual(server.calls.filter(isToken).count, 1)
    }

    func testInvalidTokenRefreshesOnceAndRetries() async throws {
        let refreshes = Counter()
        let server = MockServer { call, _ in
            if isToken(call) { return .json(tokenJSON(refreshes.next())) }
            return call.auth == "Bearer nfa_1"
                ? .json(["statusCode": 401, "name": "invalid_token", "message": "expired"], status: 401)
                : .json(statusJSON)
        }
        _ = try await open(server).status()
        XCTAssertEqual(refreshes.value, 2)
        XCTAssertEqual(server.calls.filter { !isToken($0) }.map(\.auth), ["Bearer nfa_1", "Bearer nfa_2"])
    }

    func testRejectedRefreshIsConnectionRevoked() async throws {
        let server = MockServer([grantError])
        await assertError(try await open(server).status(), statusCode: 400, name: "connection_revoked")
        XCTAssertTrue(server.calls.allSatisfy(isToken))
        let forbidden = MockServer([.json(["statusCode": 403, "name": "forbidden", "message": "x"], status: 403)])
        await assertError(try await open(forbidden).status(), statusCode: 403, name: "connection_revoked")
    }

    func testPersistFailureIsRetriedWithoutNewRefresh() async throws {
        let server = MockServer { call, _ in isToken(call) ? .json(tokenJSON(1)) : .json(statusJSON) }
        let saved = Saved()
        saved.failures = 1
        let connection = try open(server, saved: saved)
        do {
            _ = try await connection.status()
            XCTFail("hata bekleniyordu")
        } catch let error as NafruError {
            XCTAssertEqual(error.name, "token_persist_failed")
            XCTAssertTrue(error.message.contains("disk dolu"))
        }
        _ = try await connection.status()
        XCTAssertEqual(saved.all, ["nfr_1"])
        XCTAssertEqual(server.calls.filter(isToken).count, 1)
    }

    func testConnectionEndpoints() async throws {
        let server = MockServer { call, _ in
            if isToken(call) { return .json(tokenJSON(1)) }
            switch call.path {
            case "/senders": return .json(["domains": [["id": "d1", "name": "acme.test"]], "default_from": NSNull()])
            case "/emails" where call.method == "POST": return .json(["id": "e1"])
            case "/emails/e1": return .json(emailJSON)
            default: return .json(["object": "list", "data": [], "has_more": false])
            }
        }
        let connection = try open(server)
        _ = try await connection.senders.list()
        _ = try await connection.templates.list()
        _ = try await connection.emails.send(SendEmailInput(from: "a@b.co", to: ["c@d.co"], subject: "s", html: "<p>x</p>"), idempotencyKey: "k1")
        _ = try await connection.emails.get("e1")
        _ = try await connection.emails.list()
        XCTAssertEqual(server.calls.filter { !isToken($0) }.map { "\($0.method) \($0.path)" },
                       ["GET /senders", "GET /templates", "POST /emails", "GET /emails/e1", "GET /emails"])
    }

    func testServerErrorPropagates() async throws {
        let server = MockServer { call, _ in
            isToken(call) ? .json(tokenJSON(1)) : .json(["statusCode": 403, "name": "insufficient_scope", "message": "scope"], status: 403)
        }
        await assertError(try await open(server).templates.list(), statusCode: 403, name: "insufficient_scope")
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
