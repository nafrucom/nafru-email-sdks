import Foundation
import XCTest
@testable import NafruEmail

final class ResourceTests: XCTestCase {
    func testContactTopicsUpdateSendsBareArray() async throws {
        let server = MockServer([.json(["object": "contact", "id": "c1"])])
        _ = try await client(server).contacts.topics.update("c1", UpdateContactTopicsInput(topics: [.init(id: "t1", subscription: .optIn)]))
        XCTAssertEqual(server.calls[0].method, "PATCH")
        XCTAssertEqual(server.calls[0].path, "/contacts/c1/topics")
        XCTAssertTrue(jsonEqual(server.calls[0].json, [["id": "t1", "subscription": "opt_in"]]))
    }

    func testPathSegmentsAreEncoded() async throws {
        let server = MockServer([.json(["object": "contact", "contact": "x", "deleted": true])])
        _ = try await client(server).contacts.remove("a+b@x.test")
        XCTAssertEqual(server.calls[0].url, "https://api.test/contacts/a%2Bb%40x.test")
    }

    func testExplicitNullVersusOmitted() async throws {
        let server = MockServer([.json(["object": "contact", "id": "c1"])])
        _ = try await client(server).contacts.update("c1", UpdateContactInput(firstName: .some(nil), properties: ["plan": "pro", "seats": 3, "old": nil]))
        XCTAssertTrue(jsonEqual(server.calls[0].json, ["first_name": NSNull(), "properties": ["plan": "pro", "seats": 3, "old": NSNull()]]))
    }

    func testRoutes() async throws {
        let server = MockServer([.json([:])])
        let nafru = try client(server)
        _ = try? await nafru.segments.contacts("s1", SegmentContactsQuery(limit: 3))
        _ = try? await nafru.contacts.segments.add("c1", "s1")
        _ = try? await nafru.templates.putTranslation("welcome", locale: "pt-BR", PutTemplateTranslationInput(html: "<p/>"))
        _ = try? await nafru.events.send(SendEventInput(name: "plan_upgraded", contact: .email("ali@example.org")))
        _ = try? await nafru.emails.update("e1", scheduledAt: "in 1 hour")
        XCTAssertEqual(server.calls.map { "\($0.method) \($0.url)" }, [
            "GET https://api.test/segments/s1/contacts?limit=3",
            "POST https://api.test/contacts/c1/segments/s1",
            "PUT https://api.test/templates/welcome/translations/pt-BR",
            "POST https://api.test/events",
            "PATCH https://api.test/emails/e1"
        ])
        XCTAssertTrue(jsonEqual(server.calls[3].json, ["name": "plan_upgraded", "contact": ["email": "ali@example.org"]]))
        XCTAssertTrue(jsonEqual(server.calls[4].json, ["scheduled_at": "in 1 hour"]))
    }

    func testPaginationFollowsAfterCursor() async throws {
        let pages: [Reply] = [
            .json(["object": "list", "data": [contactJSON("a"), contactJSON("b")], "has_more": true]),
            .json(["object": "list", "data": [contactJSON("c")], "has_more": false])
        ]
        let server = MockServer(pages)
        let nafru = try client(server)
        var ids: [String] = []
        for try await contact in paginate(nafru.contacts.list, ListContactsQuery(limit: 2)) { ids.append(contact.id) }
        XCTAssertEqual(ids, ["a", "b", "c"])
        XCTAssertEqual(server.calls.map(\.url), ["https://api.test/contacts?limit=2", "https://api.test/contacts?limit=2&after=b"])
    }

    func testPaginationThrowsOnError() async throws {
        let server = MockServer([.json(["statusCode": 401, "name": "unauthorized", "message": "anahtar yok"], status: 401)])
        let nafru = try client(server)
        do {
            for try await _ in paginate(nafru.contacts.list, ListContactsQuery()) {}
            XCTFail("hata bekleniyordu")
        } catch let error as NafruError {
            XCTAssertEqual(error.statusCode, 401)
            XCTAssertEqual(error.message, "anahtar yok")
        }
    }
}

func contactJSON(_ id: String) -> [String: Any] {
    ["id": id, "email": "\(id)@x.test", "first_name": NSNull(), "last_name": NSNull(), "unsubscribed": false,
     "locale": NSNull(), "created_at": "2026-01-01T00:00:00Z"]
}

final class BroadcastTests: XCTestCase {
    private func broadcastJSON(recurrence: Any, dataSource: Any) -> [String: Any] {
        [
            "object": "broadcast", "id": "b1", "name": "Bülten", "segment_id": "s1", "audience_id": "s1", "subject": "Hafta",
            "status": "draft", "created_at": "2026-01-01T00:00:00Z", "scheduled_at": NSNull(), "sent_at": NSNull(),
            "recurrence": recurrence, "trigger_state": "active", "next_run_at": "2026-01-05T09:00:00Z", "parent_id": NSNull(),
            "from": "a@x.test", "reply_to": NSNull(), "preview_text": NSNull(), "topic_id": NSNull(), "template_id": NSNull(),
            "html": "<p>{{{data.title}}}</p>", "text": NSNull(), "open_tracking": true, "click_tracking": false,
            "finished_at": NSNull(), "failure_reason": NSNull(), "data": ["title": "Merhaba"], "data_source": dataSource
        ]
    }

    func testDecodesRecurrenceAndUrlDataSource() async throws {
        let server = MockServer([
            .json(broadcastJSON(recurrence: ["type": "weekly", "days": [1, 3], "time": "09:00"],
                                dataSource: ["type": "url", "url": "https://acme.test/feed", "header_name": "X-Key", "has_header_value": true])),
            .json(broadcastJSON(recurrence: ["type": "yearly", "month": 1], dataSource: ["type": "kafka"]))
        ])
        let nafru = try client(server)
        let broadcast = try await nafru.broadcasts.get("b1")
        XCTAssertEqual(broadcast.recurrence, .weekly(days: [1, 3], time: "09:00"))
        XCTAssertEqual(broadcast.dataSource, .url("https://acme.test/feed", headerName: "X-Key", hasHeaderValue: true))
        XCTAssertEqual(broadcast.triggerState, "active")
        XCTAssertEqual(broadcast.nextRunAt, "2026-01-05T09:00:00Z")
        XCTAssertNil(broadcast.parentId)
        XCTAssertEqual(broadcast.data, ["title": "Merhaba"])
        // Bilinmeyen tür çözümlemeyi kırmaz.
        let future = try await nafru.broadcasts.get("b1")
        XCTAssertEqual(future.recurrence, .unknown(type: "yearly"))
        XCTAssertEqual(future.dataSource, .unknown(type: "kafka"))
    }

    func testEncodesRecurrenceDataSourceAndNulls() async throws {
        let server = MockServer([.json(["object": "broadcast", "id": "b1"])])
        let nafru = try client(server)
        _ = try await nafru.broadcasts.create(CreateBroadcastInput(
            segmentId: "s1", from: "a@x.test", html: "<p/>", data: ["title": "Merhaba"],
            dataSource: .url("https://acme.test/feed", headerName: "X-Key", headerValue: .some(nil)),
            recurrence: .interval(everyDays: 7, time: "09:00")
        ))
        XCTAssertTrue(jsonEqual(server.calls[0].json, [
            "segment_id": "s1", "from": "a@x.test", "html": "<p/>", "data": ["title": "Merhaba"],
            "data_source": ["type": "url", "url": "https://acme.test/feed", "header_name": "X-Key", "header_value": NSNull()],
            "recurrence": ["type": "interval", "every_days": 7, "time": "09:00"]
        ]))
        _ = try await nafru.broadcasts.update("b1", UpdateBroadcastInput(data: .some(nil), dataSource: .webhook(regenerateSecret: true), recurrence: .some(nil)))
        XCTAssertTrue(jsonEqual(server.calls[1].json, ["data": NSNull(), "data_source": ["type": "webhook", "regenerate_secret": true], "recurrence": NSNull()]))
        _ = try await nafru.broadcasts.send("b1", SendBroadcastInput(data: ["title": "Bugün"]))
        XCTAssertTrue(jsonEqual(server.calls[2].json, ["data": ["title": "Bugün"]]))
    }
}
