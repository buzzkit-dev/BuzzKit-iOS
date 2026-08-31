import Foundation
import Testing
@testable import BuzzKit

@Suite struct DeepLinkTests {
    @Test func registryRunsRegisteredHandler() throws {
        let registry = ActionRegistry()
        let received = LockedState<RemoteAction?>(nil)
        registry.register("show_offer") { action in
            received.write(action)
        }
        let action = try #require(RemoteAction(raw: ["name": "show_offer", "data": ["id": "1"]]))
        registry.handler(for: "show_offer")?(action)
        #expect(received.read()?.data["id"] == .string("1"))
        registry.unregister("show_offer")
        #expect(registry.handler(for: "show_offer") == nil)
    }

    @Test func unknownActionHasNoHandler() {
        let registry = ActionRegistry()
        #expect(registry.handler(for: "missing") == nil)
    }
}
