import Foundation
import Testing
@testable import BuzzKit

@Suite struct IdentityStoreTests {
    private func makeStore() -> KeyValueStore {
        let defaults = UserDefaults(suiteName: "buzzkit-tests-\(UUID().uuidString)")!
        return KeyValueStore(defaults: defaults)
    }

    @Test func startsAnonymousWithStableId() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        let first = await store.current
        #expect(first.isAnonymous)
        #expect(first.externalId.hasPrefix("anon_"))
        let again = IdentityStore(store: keyValue)
        let second = await again.current
        #expect(second.externalId == first.externalId)
    }

    @Test func identifySwitchesAndPersists() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        let (identity, changed) = await store.identify(externalId: "user_42", identityHash: "hash")
        #expect(changed)
        #expect(!identity.isAnonymous)
        #expect(identity.externalId == "user_42")
        #expect(identity.identityHash == "hash")
        let (_, changedAgain) = await store.identify(externalId: "user_42", identityHash: "hash")
        #expect(!changedAgain)
        let reloaded = IdentityStore(store: keyValue)
        let current = await reloaded.current
        #expect(current.externalId == "user_42")
    }

    @Test func logoutReturnsToFreshAnonymous() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        let original = await store.current
        _ = await store.identify(externalId: "user_42", identityHash: "hash")
        let after = await store.logout()
        #expect(after.isAnonymous)
        #expect(after.identityHash == nil)
        #expect(after.externalId != original.externalId)
        #expect(after.externalId.hasPrefix("anon_"))
    }
}
