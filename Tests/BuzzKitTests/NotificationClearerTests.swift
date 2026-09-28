import Foundation
import Testing
@testable import BuzzKit

private final class FakeDeliveredStore: ActiveNotificationStore, @unchecked Sendable {
    private let state: LockedState<(notifications: [ActiveNotification], badges: [Int])>

    init(_ notifications: [ActiveNotification]) {
        state = LockedState((notifications: notifications, badges: []))
    }

    var remaining: [String] { state.read().notifications.map(\.identifier) }
    var badgeResets: Int { state.read().badges.filter { $0 == 0 }.count }
    var badge: Int? { state.read().badges.last }

    func active() async -> [ActiveNotification] {
        state.read().notifications
    }

    func remove(identifiers: [String]) {
        state.withLock { $0.notifications.removeAll { identifiers.contains($0.identifier) } }
    }

    func setBadge(_ count: Int) async {
        state.withLock { $0.badges.append(count) }
    }
}

private func delivered(_ identifier: String, thread: String? = nil, data: [String: Any] = [:]) -> ActiveNotification {
    var userInfo: [AnyHashable: Any] = ["bk": ["messageId": "msg_" + identifier]]
    for (key, value) in data { userInfo[key] = value }
    return ActiveNotification(
        identifier: identifier,
        payload: PushPayload(userInfo: userInfo)!,
        title: "Title",
        body: "Body",
        threadId: thread,
        deliveredAt: Date()
    )
}

@Suite struct NotificationClearerTests {
    private func makeClearer(
        _ notifications: [ActiveNotification],
        policy: BuzzKit.NotificationClearing = .default
    ) -> (NotificationClearer, FakeDeliveredStore) {
        let store = FakeDeliveredStore(notifications)
        return (NotificationClearer(store: store, policy: policy, logger: BKLogger(level: .none)), store)
    }

    @Test func appOpenClearsNothingByDefault() async {
        let (clearer, store) = makeClearer([delivered("a"), delivered("b", thread: "room:1")])
        await clearer.appOpened()
        #expect(store.remaining == ["a", "b"])
        #expect(store.badge == nil)
    }

    @Test func tappingAThreadByDefaultClearsItAndCountsTheBadgeDown() async {
        let (clearer, store) = makeClearer([
            delivered("a", thread: "room:1"),
            delivered("b", thread: "room:1"),
            delivered("c", thread: "room:2"),
            delivered("d"),
        ])
        await clearer.notificationOpened(thread: "room:1")
        #expect(store.remaining == ["c", "d"])
        #expect(store.badge == 2)
    }

    @Test func allPolicyClearsThreadsOnAppOpenToo() async {
        let (clearer, store) = makeClearer([delivered("a"), delivered("b", thread: "room:1")], policy: .all)
        await clearer.appOpened()
        #expect(store.remaining.isEmpty)
        #expect(store.badgeResets == 1)
    }

    @Test func threadsOnlyPolicyKeepsUnthreadedOnAppOpen() async {
        let (clearer, store) = makeClearer([delivered("a"), delivered("b", thread: "room:1")], policy: .threads)
        await clearer.appOpened()
        #expect(store.remaining == ["a"])
    }

    @Test func badgeOnlyPolicyKeepsActiveNotifications() async {
        let (clearer, store) = makeClearer([delivered("a")], policy: .badge)
        await clearer.appOpened()
        #expect(store.remaining == ["a"])
        #expect(store.badgeResets == 1)
    }

    @Test func deliveredOnlyPolicyKeepsBadge() async {
        let (clearer, store) = makeClearer([delivered("a")], policy: .unthreaded)
        await clearer.appOpened()
        #expect(store.remaining.isEmpty)
        #expect(store.badgeResets == 0)
    }

    @Test func emptyPolicyDoesNothing() async {
        let (clearer, store) = makeClearer([delivered("a", thread: "room:1")], policy: [])
        await clearer.start()
        await clearer.notificationOpened(thread: "room:1")
        #expect(store.remaining == ["a"])
        #expect(store.badgeResets == 0)
    }

    @Test func clearingAThreadLeavesOtherThreadsAndTheBadge() async {
        let (clearer, store) = makeClearer([
            delivered("a", thread: "room:1"),
            delivered("b", thread: "room:2"),
            delivered("c"),
        ])
        await clearer.clear(inThread: "room:1")
        #expect(store.remaining == ["b", "c"])
        #expect(store.badgeResets == 0)
    }

    @Test func clearingByPredicateReadsThePayload() async {
        let (clearer, store) = makeClearer([
            delivered("a", data: ["orderId": "o_1"]),
            delivered("b", data: ["orderId": "o_2"]),
        ])
        await clearer.clear { $0.payload.data["orderId"] == .string("o_2") }
        #expect(store.remaining == ["a"])
    }

    @Test func openingAThreadedNotificationClearsItsThreadOnly() async {
        let (clearer, store) = makeClearer([
            delivered("a", thread: "room:1"),
            delivered("b", thread: "room:1"),
            delivered("c", thread: "room:2"),
        ], policy: .tappedThread)
        await clearer.notificationOpened(thread: "room:1")
        #expect(store.remaining == ["c"])
        #expect(store.badge == 1)
    }

    @Test func openingWithoutThreadOrWithoutThePolicyKeepsEverything() async {
        let (withPolicy, storeWithPolicy) = makeClearer([delivered("a", thread: "room:1")], policy: .tappedThread)
        await withPolicy.notificationOpened(thread: nil)
        #expect(storeWithPolicy.remaining == ["a"])

        let (withoutPolicy, storeWithoutPolicy) = makeClearer([delivered("a", thread: "room:1")], policy: .badge)
        await withoutPolicy.notificationOpened(thread: "room:1")
        #expect(storeWithoutPolicy.remaining == ["a"])
    }

    @Test func aBackgroundLaunchClearsNothingUntilTheAppIsOpened() async {
        let store = FakeDeliveredStore([delivered("a")])
        let clearer = NotificationClearer(
            store: store,
            policy: .all,
            logger: BKLogger(level: .none),
            isInForeground: { false }
        )

        await clearer.start()
        #expect(store.remaining == ["a"])
        #expect(store.badgeResets == 0)

        await clearer.appOpened()
        #expect(store.remaining.isEmpty)
        #expect(store.badgeResets == 1)
    }

    @Test func aForegroundLaunchClearsRightAway() async {
        let store = FakeDeliveredStore([delivered("a")])
        let clearer = NotificationClearer(
            store: store,
            policy: .all,
            logger: BKLogger(level: .none),
            isInForeground: { true }
        )

        await clearer.start()
        #expect(store.remaining.isEmpty)
    }

    @Test func nothingMatchedRemovesNothing() async {
        let (clearer, store) = makeClearer([delivered("a", thread: "room:1")])
        await clearer.clear(inThread: "room:9")
        #expect(store.remaining == ["a"])
    }
}
