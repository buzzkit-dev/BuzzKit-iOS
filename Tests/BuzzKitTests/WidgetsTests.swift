import Foundation
import Testing
@testable import BuzzKit

@Suite struct WidgetsTests {
    private func store() -> KeyValueStore {
        KeyValueStore(defaults: UserDefaults(suiteName: "buzzkit-widgets-\(UUID().uuidString)")!)
    }

    @Test func registersAndDeletesOnTheClientWidgetRoutes() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(200, #"{"success":true,"data":{"id":"wgt_1","environment":"sandbox"}}"#) }
        let api = ClientAPI(http: mock.client())

        let widget = try await api.registerWidget(
            RegisterWidgetBody(externalId: "u1", identityHash: "h", token: "ab12", environment: "sandbox")
        )
        try await api.deleteWidget(id: widget.id, identity: SubscriberIdentity(externalId: "u1", identityHash: "h"))

        let requests = mock.requests()
        #expect(requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
            "POST /v1/client/widgets",
            "DELETE /v1/client/widgets/wgt_1",
        ])
        let body = try JSONSerialization.jsonObject(with: bodyData(of: requests[0])) as? [String: Any]
        #expect(body?["token"] as? String == "ab12")
        #expect(body?["environment"] as? String == "sandbox")
        #expect(body?["externalId"] as? String == "u1")
        #expect(requests[1].value(forHTTPHeaderField: "BuzzKit-Subscriber") == "u1")
        #expect(requests[1].value(forHTTPHeaderField: "BuzzKit-Identity") == "h")
    }

    @Test func identityPrefersTheSignedInSubscriber() throws {
        let shared = store()
        shared.set("anon_1", for: StorageKey.anonymousId)
        shared.set("user_1", for: StorageKey.externalId)
        shared.set("hash", for: StorageKey.identityHash)

        let identity = try BuzzKit.Widgets.identity(in: shared)
        #expect(identity.externalId == "user_1")
        #expect(identity.identityHash == "hash")
    }

    @Test func identityFallsBackToTheAnonymousSubscriberWithoutAHash() throws {
        let shared = store()
        shared.set("anon_1", for: StorageKey.anonymousId)
        shared.set("stale", for: StorageKey.identityHash)

        let identity = try BuzzKit.Widgets.identity(in: shared)
        #expect(identity.externalId == "anon_1")
        #expect(identity.identityHash == nil)
    }

    @Test func identityThrowsBeforeTheAppHasConfiguredBuzzKit() {
        #expect(throws: BuzzKitError.self) { try BuzzKit.Widgets.identity(in: store()) }
    }
}
