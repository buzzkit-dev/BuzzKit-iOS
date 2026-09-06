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
        let (identity, changed, _) = await store.identify(externalId: "user_42", identityHash: "hash")
        #expect(changed)
        #expect(!identity.isAnonymous)
        #expect(identity.externalId == "user_42")
        #expect(identity.identityHash == "hash")
        let (_, changedAgain, _) = await store.identify(externalId: "user_42", identityHash: "hash")
        #expect(!changedAgain)
        let reloaded = IdentityStore(store: keyValue)
        let current = await reloaded.current
        #expect(current.externalId == "user_42")
    }

    @Test func identifyReportsTheAnonymousIdItCameFrom() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        let anonymous = await store.current.externalId

        let (_, _, mergedFrom) = await store.identify(externalId: "user_42", identityHash: nil)
        #expect(mergedFrom == anonymous)
    }

    @Test func identifyKeepsReportingTheMergeUntilItIsSettled() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        let anonymous = await store.current.externalId
        _ = await store.identify(externalId: "user_42", identityHash: nil)

        let (_, _, again) = await store.identify(externalId: "user_42", identityHash: nil)
        #expect(again == anonymous)

        await store.settleMerge()

        let (_, _, settled) = await store.identify(externalId: "user_42", identityHash: nil)
        #expect(settled == nil)
    }

    @Test func identifyReportsNothingToMergeOnceTheDeviceIsIdentified() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        _ = await store.identify(externalId: "user_42", identityHash: nil)
        await store.settleMerge()

        let (_, _, switched) = await store.identify(externalId: "user_99", identityHash: nil)
        #expect(switched == nil)
    }

    @Test func aPendingMergeSurvivesRelaunch() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        let anonymous = await store.current.externalId
        _ = await store.identify(externalId: "user_42", identityHash: nil)

        let relaunched = IdentityStore(store: keyValue)
        #expect(await relaunched.hasPendingMerge)
        let (_, _, mergedFrom) = await relaunched.identify(externalId: "user_42", identityHash: nil)
        #expect(mergedFrom == anonymous)

        await relaunched.settleMerge()
        let afterSettle = IdentityStore(store: keyValue)
        #expect(!(await afterSettle.hasPendingMerge))
    }

    @Test func logoutDropsAPendingMerge() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        _ = await store.identify(externalId: "user_42", identityHash: nil)
        #expect(await store.hasPendingMerge)

        _ = await store.logout()

        #expect(!(await store.hasPendingMerge))
    }

    @Test func identifyReportsTheFreshAnonymousIdAfterLogout() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        _ = await store.identify(externalId: "user_42", identityHash: nil)
        await store.settleMerge()
        let second = await store.logout()

        let (_, _, mergedFrom) = await store.identify(externalId: "user_42", identityHash: nil)
        #expect(mergedFrom == second.externalId)
    }

    @Test func identifyNeverMergesAnAnonymousIdIntoItself() async {
        let keyValue = makeStore()
        let store = IdentityStore(store: keyValue)
        let anonymous = await store.current.externalId

        let (_, _, mergedFrom) = await store.identify(externalId: anonymous, identityHash: nil)
        #expect(mergedFrom == nil)
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
