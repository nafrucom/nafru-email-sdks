import CryptoKit
import Foundation
import XCTest
@testable import NafruEmail

final class SecurityTests: XCTestCase {
    func testRedirectIsAnErrorAndNotRetried() async throws {
        let server = MockServer([Reply(status: 302, headers: ["Location": "https://evil.test/steal"])])
        await assertError(try await client(server, maxRetries: 2).emails.get("e1"), statusCode: 302, name: "unexpected_redirect")
        XCTAssertEqual(server.calls.count, 1)
    }

    func testDefaultTransportRefusesRedirects() {
        let task = URLSession.shared.dataTask(with: URL(string: "https://api.test")!)
        let response = HTTPURLResponse(url: URL(string: "https://api.test")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        var followed: URLRequest? = URLRequest(url: URL(string: "https://placeholder.test")!)
        NoRedirectDelegate.shared.urlSession(URLSession.shared, task: task, willPerformHTTPRedirection: response,
                                             newRequest: URLRequest(url: URL(string: "https://evil.test")!)) { followed = $0 }
        XCTAssertNil(followed)
    }

    func testHTTPSRequiredExceptLoopback() throws {
        for url in ["http://api.example.com/api", "ftp://x.test", "not a url", "http://127.0.0.1.evil.test"] {
            XCTAssertThrowsError(try NafruEmail("k", baseURL: url), url) { XCTAssertEqual(($0 as! NafruError).name, "invalid_argument") }
        }
        for url in ["https://email.nafru.com/api", "http://localhost:48787/api", "http://app.localhost/api", "http://127.0.0.1:48787/api", "http://[::1]:48787/api"] {
            XCTAssertNoThrow(try NafruEmail("k", baseURL: url), url)
        }
        XCTAssertThrowsError(try NafruConnect(clientId: "a", clientSecret: "s", baseURL: "http://api.example.com/api"))
        XCTAssertThrowsError(try NafruConnect(clientId: "a", clientSecret: "s", webURL: "http://web.example.com"))
    }

    func testUnsafePathSegmentsRejectedBeforeRequest() async throws {
        let server = MockServer([.json(emailJSON)])
        let nafru = try client(server)
        for id in ["", ".", ".."] {
            await assertError(try await nafru.emails.get(id), statusCode: nil, name: "invalid_argument")
        }
        await assertError(try await nafru.templates.removeTranslation("welcome", locale: ".."), statusCode: nil, name: "invalid_argument")
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testIdempotencyKeyHeaderInjectionRejected() async throws {
        let server = MockServer([.json(["id": "e1"])])
        let nafru = try client(server)
        for key in ["", "a\r\nX-Evil: 1", "a\nb", "tab\there"] {
            await assertError(try await nafru.emails.send(SendEmailInput(to: ["x"], text: "t"), idempotencyKey: key), statusCode: nil, name: "invalid_argument")
        }
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testResponseTooLarge() async throws {
        let server = MockServer([Reply(status: 200, body: Data(count: maxResponseBytes + 1))])
        await assertError(try await client(server).emails.get("e1"), statusCode: 200, name: "response_too_large")
    }

    func testSecretsAreRedactedInDescriptions() throws {
        let secrets = ["nafru_supersecret", "nfs_clientsecret", "nfr_refreshsecret"]
        let nafru = try NafruEmail("nafru_supersecret", transport: MockServer([]))
        let connect = try NafruConnect(clientId: "app_x", clientSecret: "nfs_clientsecret", transport: MockServer([]))
        let grant = ConnectionGrant(connectionId: "conn_1", refreshToken: "nfr_refreshsecret", scopes: [.emailsSend])
        let options = ConnectionOptions(refreshToken: "nfr_refreshsecret") { _ in }
        let connection = connect.connection("conn_1", options)
        var rendered = ""
        for value in [nafru, connect, grant, options, connection, ConnectionTokens(refreshToken: "nfr_refreshsecret")] as [Any] {
            rendered += "\(value) \(String(reflecting: value)) "
            dump(value, to: &rendered)
        }
        for secret in secrets { XCTAssertFalse(rendered.contains(secret), secret) }
        XCTAssertTrue(rendered.contains("nfr_****"))
        XCTAssertTrue(rendered.contains("conn_1"))
    }

    func testWebhookEdgeCases() throws {
        let secret = "whsec_" + Data("0123456789abcdef0123456789abcdef".utf8).base64EncodedString()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sign = { (id: String, ts: String, body: String) -> String in
            let key = SymmetricKey(data: Data(base64Encoded: String(secret.dropFirst(6)))!)
            return "v1," + Data(HMAC<SHA256>.authenticationCode(for: Data("\(id).\(ts).\(body)".utf8), using: key)).base64EncodedString()
        }
        let ts = "1800000000"
        let good = sign("msg_1", ts, "{}")
        // Eksik başlıklar: false, çökme yok.
        XCTAssertFalse(try verifyWebhook(payload: "{}", headers: WebhookHeaders(id: "", timestamp: ts, signature: good), secret: secret, now: now))
        XCTAssertFalse(try verifyWebhook(payload: "{}", headers: WebhookHeaders(id: "msg_1", timestamp: "", signature: good), secret: secret, now: now))
        XCTAssertFalse(try verifyWebhook(payload: "{}", headers: WebhookHeaders(id: "msg_1", timestamp: ts, signature: ""), secret: secret, now: now))
        // Ham bayt sürümü.
        XCTAssertTrue(try verifyWebhook(payload: Data("{}".utf8), headers: WebhookHeaders(id: "msg_1", timestamp: ts, signature: good), secret: secret, now: now))
        // Gelecekteki zaman damgası da sınırlı.
        let future = "1800000301"
        XCTAssertFalse(try verifyWebhook(payload: "{}", headers: WebhookHeaders(id: "msg_1", timestamp: future, signature: sign("msg_1", future, "{}")), secret: secret, now: now))
        // 32 imzadan sonrası yok sayılır.
        let padded = Array(repeating: "v1,AAAA", count: 32).joined(separator: " ")
        XCTAssertFalse(try verifyWebhook(payload: "{}", headers: WebhookHeaders(id: "msg_1", timestamp: ts, signature: "\(padded) \(good)"), secret: secret, now: now))
        XCTAssertTrue(try verifyWebhook(payload: "{}", headers: WebhookHeaders(id: "msg_1", timestamp: ts, signature: "\(Array(repeating: "v1,AAAA", count: 31).joined(separator: " ")) \(good)"), secret: secret, now: now))
    }
}
