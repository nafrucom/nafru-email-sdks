import CryptoKit
import Foundation
import XCTest
@testable import NafruEmail

final class WebhookTests: XCTestCase {
    struct Vector: Decodable {
        let secret, id, timestamp, payload, signature: String
        let now_seconds: Double
    }

    private func vector() throws -> Vector {
        // Paylaşılan test vektörü: sdks/webhook-test-vector.json
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("webhook-test-vector.json")
        return try JSONDecoder().decode(Vector.self, from: Data(contentsOf: url))
    }

    func testSharedVector() throws {
        let v = try vector()
        let now = Date(timeIntervalSince1970: v.now_seconds)
        let headers = WebhookHeaders(id: v.id, timestamp: v.timestamp, signature: v.signature)
        XCTAssertTrue(try verifyWebhook(payload: v.payload, headers: headers, secret: v.secret, now: now))
        XCTAssertFalse(try verifyWebhook(payload: v.payload + " ", headers: headers, secret: v.secret, now: now))
        XCTAssertFalse(try verifyWebhook(payload: v.payload, headers: WebhookHeaders(id: "msg_x", timestamp: v.timestamp, signature: v.signature), secret: v.secret, now: now))
        // Anahtar döndürme: birden çok imzadan biri yeterli.
        let rotated = WebhookHeaders(id: v.id, timestamp: v.timestamp, signature: "v1,bozuk \(v.signature) v2,x")
        XCTAssertTrue(try verifyWebhook(payload: v.payload, headers: rotated, secret: v.secret, now: now))
    }

    func testTimestampTolerance() throws {
        let v = try vector()
        let headers = WebhookHeaders(id: v.id, timestamp: v.timestamp, signature: v.signature)
        XCTAssertFalse(try verifyWebhook(payload: v.payload, headers: headers, secret: v.secret, now: Date(timeIntervalSince1970: v.now_seconds + 301)))
        XCTAssertFalse(try verifyWebhook(payload: v.payload, headers: WebhookHeaders(id: v.id, timestamp: "abc", signature: v.signature), secret: v.secret,
                                         now: Date(timeIntervalSince1970: v.now_seconds)))
    }

    func testBadSecretThrows() {
        let headers = WebhookHeaders(id: "a", timestamp: "1", signature: "v1,x")
        XCTAssertThrowsError(try verifyWebhook(payload: "", headers: headers, secret: "sec")) {
            XCTAssertTrue(($0 as! NafruError).message.contains("whsec_"))
        }
        XCTAssertThrowsError(try verifyWebhook(payload: "", headers: headers, secret: "whsec_!!!"))
    }
}

final class DevOutboxTests: XCTestCase {
    func testWritesFilesInsteadOfSending() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nafru-outbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let server = MockServer { _, _ in XCTFail("istek gönderilmemeli"); return .json([:]) }
        let nafru = try NafruEmail("k", baseURL: "https://api.test", transport: server, devOutbox: .directory(dir.path))

        let sent = try await nafru.emails.send(SendEmailInput(
            from: "a@x.com", to: ["b@y.com", "c@y.com"], subject: "Merhaba", html: "<p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p>"
        ))
        let batch = try await nafru.emails.batch([BatchEmailItem(from: "a@x.com", to: ["d@y.com"], subject: "S", text: "düz")])

        XCTAssertTrue(sent.id.hasPrefix("dev_"))
        XCTAssertEqual(batch.data.count, 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files.filter { $0.hasSuffix(".txt") }.count, 2)
        XCTAssertEqual(files.filter { $0.hasSuffix(".html") }.count, 2)
        let base = dir.appendingPathComponent(files.first { $0.contains(sent.id) && $0.hasSuffix(".txt") }!)
        let text = try String(contentsOf: base, encoding: .utf8)
        XCTAssertTrue(text.contains("To: b@y.com, c@y.com"))
        XCTAssertTrue(text.contains("Subject: Merhaba"))
        XCTAssertTrue(text.contains("Selam Ali\n& hoş geldin"))
        let html = try String(contentsOf: base.deletingPathExtension().appendingPathExtension("html"), encoding: .utf8)
        XCTAssertTrue(html.contains("<b>Ali</b>"))
        XCTAssertTrue(server.calls.isEmpty)
    }

    func testDefaultOnlyInDevelopment() {
        XCTAssertEqual(resolveDevOutbox(nil, environment: ["NODE_ENV": "development"]), ".nafru/emails")
        XCTAssertNil(resolveDevOutbox(.disabled, environment: ["NODE_ENV": "development"]))
        XCTAssertNil(resolveDevOutbox(nil, environment: ["NODE_ENV": "production"]))
        XCTAssertEqual(resolveDevOutbox(.directory("tmp/mail"), environment: [:]), "tmp/mail")
    }
}
