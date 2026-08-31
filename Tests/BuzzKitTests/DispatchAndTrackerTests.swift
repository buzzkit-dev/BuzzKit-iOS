import Foundation
import Testing
@testable import BuzzKit

@Suite struct DeepLinkDispatchTests {
    private func payload(_ userInfo: [AnyHashable: Any]) -> PushPayload {
        PushPayload(userInfo: userInfo)!
    }

    @Test func actionTracksHandledAndRunsHandler() {
        let center = DeepLinkCenter(logger: BKLogger(level: .none))
        let ran = LockedState(false)
        center.actions.register("show_offer") { _ in ran.write(true) }
        let tracked = LockedState<[(String, [String: JSONValue])]>([])
        center.dispatch(
            payload: payload(["bk": ["messageId": "msg_1", "action": ["name": "show_offer"]]]),
            delegateRoute: { _ in false },
            track: { name, data in tracked.withLock { $0.append((name, data)) } }
        )
        #expect(ran.read())
        let events = tracked.read()
        #expect(events.count == 1)
        #expect(events[0].0 == EventNames.actionTriggered)
        #expect(events[0].1["handled"] == .bool(true))
        #expect(events[0].1["messageId"] == .string("msg_1"))
    }

    @Test func missingHandlerTracksHandledFalse() {
        let center = DeepLinkCenter(logger: BKLogger(level: .none))
        let tracked = LockedState<[[String: JSONValue]]>([])
        center.dispatch(
            payload: payload(["bk": ["action": ["name": "ghost"]]]),
            delegateRoute: { _ in false },
            track: { _, data in tracked.withLock { $0.append(data) } }
        )
        #expect(tracked.read().first?["handled"] == .bool(false))
    }

    @Test func deepLinkRoutingOrderAndVia() {
        let center = DeepLinkCenter(logger: BKLogger(level: .none))
        let tracked = LockedState<[[String: JSONValue]]>([])
        let opened = LockedState<URL?>(nil)

        center.dispatch(
            payload: payload(["bk": ["deepLink": "app://a"]]),
            delegateRoute: { _ in true },
            track: { _, data in tracked.withLock { $0.append(data) } }
        )
        #expect(tracked.read().last?["via"] == .string("delegate"))

        center.setDeepLinkHandler { url in opened.write(url) }
        center.dispatch(
            payload: payload(["bk": ["deepLink": "app://b"]]),
            delegateRoute: { _ in false },
            track: { _, data in tracked.withLock { $0.append(data) } }
        )
        #expect(opened.read() == URL(string: "app://b"))
        #expect(tracked.read().last?["via"] == .string("handler"))
        #expect(tracked.read().last?["url"] == .string("app://b"))
    }

    @Test func payloadWithoutLinkOrActionTracksNothing() {
        let center = DeepLinkCenter(logger: BKLogger(level: .none))
        let tracked = LockedState(0)
        center.dispatch(
            payload: payload(["bk": ["messageId": "msg_2"]]),
            delegateRoute: { _ in false },
            track: { _, _ in tracked.withLock { $0 += 1 } }
        )
        #expect(tracked.read() == 0)
    }
}

@Suite struct EventTrackerTests {
    private func makeTracker(_ mock: MockAPI) throws -> (EventTracker, EventQueue) {
        let queue = EventQueue(
            store: try SQLiteStore(path: ":memory:"),
            api: ClientAPI(http: mock.client(maxAttempts: 1)),
            logger: BKLogger(level: .none)
        )
        let identity = IdentityStore(
            store: KeyValueStore(defaults: UserDefaults(suiteName: "buzzkit-trk-\(UUID().uuidString)")!)
        )
        return (EventTracker(queue: queue, identity: identity, logger: BKLogger(level: .none)), queue)
    }

    @Test func customEventsQueueWithIdentity() async throws {
        let mock = MockAPI()
        let (tracker, queue) = try makeTracker(mock)
        await tracker.track("workout.completed", data: ["duration": 42])
        #expect(await queue.pendingCount() == 1)
    }

    @Test func reservedPrefixCustomNamesAreRejected() async throws {
        let mock = MockAPI()
        let (tracker, queue) = try makeTracker(mock)
        await tracker.track("$app.opened")
        await tracker.track("")
        await tracker.track(String(repeating: "x", count: 200))
        #expect(await queue.pendingCount() == 0)
    }

    @Test func systemNamesAreGatedToTheKnownSet() async throws {
        let mock = MockAPI()
        let (tracker, queue) = try makeTracker(mock)
        await tracker.trackSystem(EventNames.appOpened)
        await tracker.trackSystem("$made.up")
        #expect(await queue.pendingCount() == 1)
    }
}

@Suite struct ClientAPIPathTests {
    @Test func endpointsHitTheDocumentedPathsAndMethods() async throws {
        let mock = MockAPI()
        mock.stub { request in
            let path = request.url?.path ?? ""
            if path.contains("preferences") || path.contains("events") {
                return jsonResponse(200, #"{"success":true,"data":[]}"#)
            }
            return jsonResponse(200, #"{"success":true,"data":{"id":"act_1","activityId":"a1","attributesType":"T","kind":"activity"}}"#)
        }
        let api = ClientAPI(http: mock.client())
        _ = try await api.registerLiveActivity(
            RegisterLiveActivityBody(
                externalId: "u1", identityHash: nil, kind: "activity",
                activityId: "a1", attributesType: "T", token: "ab12", environment: nil
            )
        )
        try await api.endLiveActivity(id: "a1", identity: SubscriberIdentity(externalId: "u1", identityHash: nil))
        _ = try await api.preferences(identity: SubscriberIdentity(externalId: "u1", identityHash: "h"))
        _ = try await api.updatePreferences(["gym": .all(false)], identity: SubscriberIdentity(externalId: "u1", identityHash: nil))

        let requests = mock.requests()
        let seen = requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
        #expect(seen.contains("POST /v1/client/live-activities"))
        #expect(seen.contains("DELETE /v1/client/live-activities/a1"))
        #expect(seen.contains("GET /v1/client/preferences"))
        #expect(seen.contains("PATCH /v1/client/preferences"))
    }
}

@Suite struct ActivitySeenTests {
    @Test func firstSightingWinsOnce() {
        let id = "activity-\(UUID().uuidString)"
        #expect(ActivitySeen.markNew(id))
        #expect(!ActivitySeen.markNew(id))
    }
}

@Suite struct StoreEdgeTests {
    @Test func keyValueRoundTripsEveryType() {
        let store = KeyValueStore(defaults: UserDefaults(suiteName: "buzzkit-kv-\(UUID().uuidString)")!)
        store.set("hello", for: "s")
        store.set(true, for: "b")
        let now = Date()
        store.set(now, for: "d")
        #expect(store.string("s") == "hello")
        #expect(store.bool("b") == true)
        #expect(store.date("d") == now)
        store.set(nil as String?, for: "s")
        #expect(store.string("s") == nil)
        #expect(store.bool("missing") == nil)
    }

    @Test func jsonValueBridgesBothWays() {
        let value: JSONValue = ["a": 1, "b": [true, nil], "c": "x"]
        let any = value.anyValue as? [String: Any]
        #expect(any?["c"] as? String == "x")
        #expect(JSONValue(any: ["n": NSNumber(value: true)]) == ["n": true])
        #expect(JSONValue(any: Date()) == nil)
        #expect(JSONValue.null.anyValue == nil)
    }
}

@Suite struct RetryAfterTests {
    @Test func retryAfterHeaderIsHonoredOnce() async throws {
        let mock = MockAPI()
        let counter = LockedState(0)
        mock.stub { _ in
            let attempt = counter.withLock { value -> Int in
                value += 1
                return value
            }
            if attempt == 1 {
                let response = HTTPURLResponse(
                    url: URL(string: "https://api.test.buzzkit.dev")!,
                    statusCode: 429, httpVersion: nil,
                    headerFields: ["Retry-After": "0"]
                )!
                return (response, Data(#"{"success":false,"error":{"code":"rate_limited","message":"slow"}}"#.utf8))
            }
            return jsonResponse(200, #"{"success":true,"data":[]}"#)
        }
        let topics = try await mock.client().send(
            HTTPRequest(method: .get, path: "v1/client/preferences", body: nil, headers: [:]),
            as: [TopicDTO].self
        )
        #expect(topics.isEmpty)
        #expect(counter.read() == 2)
    }
}
