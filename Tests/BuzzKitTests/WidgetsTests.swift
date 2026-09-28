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

    private func extensionWidgets(_ mock: MockAPI, signedIn: Bool = true) -> (BuzzKit.Widgets, KeyValueStore) {
        let group = "buzzkit-widgets-group-\(UUID().uuidString)"
        let shared = KeyValueStore(appGroup: group)
        shared.set(mock.key, for: SharedConfigurationKey.apiKey)
        shared.set("https://api.test.buzzkit.dev", for: SharedConfigurationKey.apiURL)
        shared.set("anon_1", for: StorageKey.anonymousId)
        if signedIn {
            shared.set("user_1", for: StorageKey.externalId)
            shared.set("hash", for: StorageKey.identityHash)
        }
        var widgets = BuzzKit.widgets(appGroup: group)
        widgets.makeSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [MockURLProtocol.self]
            return URLSession(configuration: configuration)
        }
        return (widgets, shared)
    }

    @Test func theExtensionRegistersThroughTheAppGroupAndRemembersTheRegistration() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(201, #"{"success":true,"data":{"id":"wgt_9","environment":"production"}}"#) }
        let (widgets, shared) = extensionWidgets(mock)

        try await widgets.register(token: Data([0xAB, 0x01]))

        let request = try #require(mock.requests().first)
        #expect(request.url?.path == "/v1/client/widgets")
        let body = try JSONSerialization.jsonObject(with: bodyData(of: request)) as? [String: Any]
        #expect(body?["token"] as? String == "ab01")
        #expect(body?["externalId"] as? String == "user_1")
        #expect(body?["identityHash"] as? String == "hash")
        #expect(shared.string(StorageKey.widgetId) == "wgt_9")
    }

    @Test func unregisteringDeletesTheRememberedRegistrationOnce() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(200, #"{"success":true,"data":{"id":"wgt_9","environment":"production"}}"#) }
        let (widgets, shared) = extensionWidgets(mock)
        shared.set("wgt_9", for: StorageKey.widgetId)

        try await widgets.unregister()
        try await widgets.unregister()

        #expect(mock.requests().map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == ["DELETE /v1/client/widgets/wgt_9"])
        #expect(shared.string(StorageKey.widgetId) == nil)
    }

    @Test func aTokenChangeRegistersWhileWidgetsAreInstalledAndUnregistersWhenNoneAre() async throws {
        let mock = MockAPI()
        mock.stub { _ in jsonResponse(200, #"{"success":true,"data":{"id":"wgt_3","environment":"production"}}"#) }
        let (widgets, _) = extensionWidgets(mock, signedIn: false)

        try await widgets.update(token: Data([0x01]), installed: true)
        try await widgets.update(token: Data([0x01]), installed: false)

        let requests = mock.requests()
        #expect(requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
            "POST /v1/client/widgets",
            "DELETE /v1/client/widgets/wgt_3",
        ])
        let body = try JSONSerialization.jsonObject(with: bodyData(of: requests[0])) as? [String: Any]
        #expect(body?["externalId"] as? String == "anon_1")
        #expect(requests[1].value(forHTTPHeaderField: "BuzzKit-Identity") == nil)
    }

    @Test func theExtensionRefusesBeforeTheAppSharedItsConfiguration() async {
        let widgets = BuzzKit.widgets(appGroup: "buzzkit-widgets-empty-\(UUID().uuidString)")
        await #expect(throws: BuzzKitError.self) { try await widgets.register(token: Data([0x01])) }
    }
}

