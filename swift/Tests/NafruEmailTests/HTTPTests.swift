import Foundation
import XCTest
@testable import NafruEmail

final class HTTPTests: XCTestCase {
    func testSendHeadersAndIdempotencyKey() async throws {
        let server = MockServer([.json(["id": "e1"])])
        let result = try await client(server).emails.send(
            SendEmailInput(from: "a@x.test", to: ["b@x.test"], subject: "s", text: "t", template: nil),
            idempotencyKey: "k-1"
        )
        XCTAssertEqual(result.id, "e1")
        let call = server.calls[0]
        XCTAssertEqual(call.url, "https://api.test/emails")
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.auth, "Bearer key_test")
        XCTAssertEqual(call.header("Content-Type"), "application/json")
        XCTAssertEqual(call.header("User-Agent"), "nafru-email-swift/\(NafruSDK.version)")
        XCTAssertEqual(call.header("Idempotency-Key"), "k-1")
        XCTAssertTrue(jsonEqual(call.json, ["from": "a@x.test", "to": ["b@x.test"], "subject": "s", "text": "t"]))
    }

    func testQueryOnlyCarriesFilledValues() async throws {
        let server = MockServer([.json(["object": "list", "data": [], "has_more": false])])
        _ = try await client(server).contacts.list(ListContactsQuery(limit: 5, after: nil, search: "ali"))
        XCTAssertEqual(server.calls[0].url, "https://api.test/contacts?limit=5&search=ali")
    }

    func testParsesErrorBody() async throws {
        let body: [String: Any] = [
            "statusCode": 422, "name": "validation_error", "message": "Geçersiz",
            "errors": [["field": "to", "message": "zorunlu", "i18nTranslationKey": "k"]]
        ]
        let server = MockServer([.json(body, status: 422)])
        do {
            _ = try await client(server).emails.send(SendEmailInput(to: ["x"], text: "t"))
            XCTFail("hata bekleniyordu")
        } catch let error as NafruError {
            XCTAssertEqual(error, NafruError(statusCode: 422, name: "validation_error", message: "Geçersiz",
                                             errors: [NafruFieldError(field: "to", message: "zorunlu", i18nTranslationKey: "k")]))
        }
    }

    func testNonStandardBodyBuildsErrorFromStatus() async throws {
        let server = MockServer([Reply(status: 502, body: Data("<html>bad gateway</html>".utf8))])
        await assertError(try await client(server).emails.get("e1"), statusCode: 502, name: "application_error")
        let notFound = MockServer([Reply(status: 404)])
        await assertError(try await client(notFound).emails.get("e1"), statusCode: 404, name: "not_found")
    }

    func testNetworkErrorHasNilStatus() async throws {
        let server = MockServer { _, _ in throw URLError(.notConnectedToInternet) }
        await assertError(try await client(server).emails.send(SendEmailInput(to: ["x"], text: "t")), statusCode: nil, name: "application_error")
    }

    func testRetries429WithRetryAfterIncludingPost() async throws {
        let limited = Reply.json(["statusCode": 429, "name": "rate_limit_exceeded", "message": "yavaş"], status: 429, headers: ["Retry-After": "0"])
        let server = MockServer([limited, .json(["id": "e1"])])
        let result = try await client(server, maxRetries: 2).emails.send(SendEmailInput(to: ["x"], text: "t"))
        XCTAssertEqual(result.id, "e1")
        XCTAssertEqual(server.calls.count, 2)
    }

    func testExhausted429ReturnsRetryAfter() async throws {
        let limited = Reply.json(["statusCode": 429, "name": "rate_limit_exceeded", "message": "yavaş"], status: 429, headers: ["Retry-After": "0"])
        let server = MockServer([limited])
        do {
            _ = try await client(server, maxRetries: 1).emails.get("e1")
            XCTFail("hata bekleniyordu")
        } catch let error as NafruError {
            XCTAssertEqual(error.statusCode, 429)
            XCTAssertEqual(error.retryAfter, 0)
        }
        XCTAssertEqual(server.calls.count, 2)
    }

    func testGet5xxRetriedButPostWithoutKeyIsNot() async throws {
        let down = Reply.json(["statusCode": 500, "name": "application_error", "message": "x"], status: 500)
        let get = MockServer([down, .json(emailJSON)])
        let email = try await client(get, maxRetries: 1).emails.get("e1")
        XCTAssertEqual(email.id, "e1")
        XCTAssertEqual(get.calls.count, 2)

        let post = MockServer([down, .json(["id": "e1"])])
        await assertError(try await client(post, maxRetries: 1).emails.send(SendEmailInput(to: ["x"], text: "t")), statusCode: 500, name: "application_error")
        XCTAssertEqual(post.calls.count, 1)
    }

    func testPostWithIdempotencyKeyRetriedAfter5xx() async throws {
        let down = Reply.json(["statusCode": 503, "name": "application_error", "message": "x"], status: 503)
        let server = MockServer([down, .json(["id": "e1"])])
        let result = try await client(server, maxRetries: 1).emails.send(SendEmailInput(to: ["x"], text: "t"), idempotencyKey: "k-1")
        XCTAssertEqual(result.id, "e1")
        XCTAssertEqual(server.calls.count, 2)
        XCTAssertEqual(server.calls[1].header("Idempotency-Key"), "k-1")
    }

    func testTimeout() async throws {
        let server = MockServer { _, _ in
            try await Task.sleep(nanoseconds: 5_000_000_000)
            return .json([:])
        }
        await assertError(try await client(server, timeout: 0.05).emails.get("e1"), statusCode: nil, name: "timeout_error")
    }

    func testApiKeyRequiredBaseURLDefaults() async throws {
        XCTAssertThrowsError(try NafruEmail("", baseURL: "https://x", transport: MockServer([]), maxRetries: 0, timeout: 30, devOutbox: nil,
                                            deprecation: DeprecationNotice(), environment: [:])) {
            XCTAssertTrue(($0 as! NafruError).message.contains("apiKey"))
        }
        let server = MockServer([.json(emailJSON)])
        _ = try await NafruEmail("k", transport: server).emails.get("e1")
        _ = try await NafruEmail("k", baseURL: "", transport: server).emails.get("e1")
        XCTAssertEqual(server.calls.map(\.url), ["https://email.nafru.com/api/emails/e1", "https://email.nafru.com/api/emails/e1"])
        XCTAssertEqual(NafruSDK.defaultBaseURL, "https://email.nafru.com/api")
    }

    func testApiKeyFallsBackToEnvironment() async throws {
        let server = MockServer([.json(emailJSON)])
        let nafru = try NafruEmail(nil, baseURL: "https://api.test", transport: server, maxRetries: 0, timeout: 30, devOutbox: .disabled,
                                   deprecation: DeprecationNotice(), environment: ["NAFRU_API_KEY": "nafru_env"])
        _ = try await nafru.emails.get("e1")
        XCTAssertEqual(server.calls[0].auth, "Bearer nafru_env")
    }

    func testDeprecationWarningPrintedOncePerClient() async throws {
        let headers = ["Deprecation": "true", "Sunset": "Wed, 01 Jul 2026 00:00:00 GMT", "Link": "<https://nafru.com/sdk>; rel=\"deprecation\""]
        let server = MockServer([.json(["id": "e1"], headers: headers), .json(["statusCode": 404, "name": "not_found", "message": "yok"], status: 404, headers: headers)])
        let messages = MessageLog()
        let nafru = try NafruEmail("k", baseURL: "https://api.test", transport: server, maxRetries: 0, timeout: 30,
                              devOutbox: .disabled, deprecation: DeprecationNotice(output: { messages.append($0) }))
        _ = try await nafru.emails.send(SendEmailInput(to: ["x"], text: "t"))
        _ = try? await nafru.emails.get("e1")
        XCTAssertEqual(messages.all, [
            "[nafru] Bu SDK sürümü (swift \(NafruSDK.version)) kullanımdan kaldırıldı; lütfen güncelleyin. Son tarih: Wed, 01 Jul 2026 00:00:00 GMT Ayrıntı: https://nafru.com/sdk"
        ])
    }
}

final class MessageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    func append(_ message: String) { lock.lock(); messages.append(message); lock.unlock() }
    var all: [String] { lock.lock(); defer { lock.unlock() }; return messages }
}

let emailJSON: [String: Any] = [
    "object": "email", "id": "e1", "to": ["b@x.test"], "from": "a@x.test", "created_at": "2026-01-01T00:00:00Z",
    "subject": "s", "bcc": NSNull(), "cc": NSNull(), "reply_to": NSNull(), "last_event": "delivered",
    "scheduled_at": NSNull(), "message_id": NSNull(), "html": NSNull(), "text": "t", "tags": [], "events": []
]

func assertError<T>(_ body: @autoclosure () async throws -> T, statusCode: Int?, name: String, file: StaticString = #filePath, line: UInt = #line) async {
    do {
        _ = try await body()
        XCTFail("hata bekleniyordu", file: file, line: line)
    } catch let error as NafruError {
        XCTAssertEqual(error.statusCode, statusCode, file: file, line: line)
        XCTAssertEqual(error.name, name, file: file, line: line)
    } catch {
        XCTFail("beklenmeyen hata: \(error)", file: file, line: line)
    }
}
