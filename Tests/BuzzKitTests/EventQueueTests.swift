import Foundation
import Testing
@testable import BuzzKit

@Suite struct EventQueueTests {
    private func makeQueue(_ mock: MockAPI, maxAttempts: Int = 1) throws -> EventQueue {
        let store = try SQLiteStore(path: ":memory:")
        return EventQueue(store: store, api: ClientAPI(http: mock.client(maxAttempts: maxAttempts)), logger: BKLogger(level: .none))
    }

    private func event(
        _ name: String,
        externalId: String = "user_1",
        identityHash: String? = nil,
        at timestamp: Date = Date()
    ) -> QueuedEvent {
        QueuedEvent(
            id: UUID().uuidString.lowercased(),
            externalId: externalId,
            identityHash: identityHash,
            name: name,
            data: ["value": 1],
            timestamp: timestamp
        )
    }

    @Test func flushSendsBatchAndClearsQueue() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(202, #"{"success":true,"data":[]}"#) }
        let queue = try makeQueue(mock)
        await queue.enqueue(event("one"))
        await queue.enqueue(event("two"))
        #expect(await queue.pendingCount() == 2)
        await queue.flush()
        #expect(await queue.pendingCount() == 0)

        let request = try #require(mock.requests().first)
        let payload = try #require(try JSONSerialization.jsonObject(with: bodyData(of: request)) as? [String: Any])
        #expect(payload["externalId"] as? String == "user_1")
        #expect(payload["source"] as? String == "ios")
        let events = try #require(payload["events"] as? [[String: Any]])
        #expect(events.count == 2)
        #expect(events.allSatisfy { ($0["id"] as? String)?.isEmpty == false })
        #expect(events.allSatisfy { ($0["timestamp"] as? String)?.contains("T") == true })
    }

    @Test func failureKeepsEventsQueued() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(500, #"{"success":false,"error":{"code":"internal","message":"boom"}}"#) }
        let queue = try makeQueue(mock)
        await queue.enqueue(event("kept"))
        await queue.flush()
        #expect(await queue.pendingCount() == 1)
    }

    @Test func flushBatchesPerIdentity() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(202, #"{"success":true,"data":[]}"#) }
        let queue = try makeQueue(mock)
        await queue.enqueue(event("anon", externalId: "anon_1", at: Date(timeIntervalSince1970: 100)))
        await queue.enqueue(event("known", externalId: "user_1", identityHash: "h", at: Date(timeIntervalSince1970: 200)))
        await queue.flush()
        #expect(await queue.pendingCount() == 0)
        #expect(mock.requests().count == 2)
    }

    @Test func deterministicRejectionDropsTheBatch() async throws {
        let mock = MockAPI()
        mock.stub { _ in
            jsonResponse(400, #"{"success":false,"error":{"code":"event_name_invalid","message":"Bad name"}}"#)
        }
        let queue = try makeQueue(mock)
        await queue.enqueue(event("bad"))
        await queue.flush()
        #expect(await queue.pendingCount() == 0)
    }

    @Test func duplicateIdsAreIgnored() async throws {
        let mock = MockAPI()
        let queue = try makeQueue(mock)
        let one = event("same")
        await queue.enqueue(one)
        await queue.enqueue(one)
        #expect(await queue.pendingCount() == 1)
    }
}
