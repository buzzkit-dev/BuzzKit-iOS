import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

protocol ActiveNotificationStore: Sendable {
    func active() async -> [ActiveNotification]
    func remove(identifiers: [String])
    func setBadge(_ count: Int) async
}

actor NotificationClearer {
    private let store: any ActiveNotificationStore
    private let policy: BuzzKit.NotificationClearing
    private let logger: BKLogger
    private let isInForeground: @Sendable () async -> Bool
    private var observer: NSObjectProtocol?

    init(
        store: any ActiveNotificationStore,
        policy: BuzzKit.NotificationClearing,
        logger: BKLogger,
        isInForeground: @escaping @Sendable () async -> Bool = NotificationClearer.systemIsInForeground
    ) {
        self.store = store
        self.policy = policy
        self.logger = logger
        self.isInForeground = isInForeground
    }

    static func systemIsInForeground() async -> Bool {
        #if canImport(UIKit) && !os(watchOS)
        return await MainActor.run { SystemOpener.sharedApplication?.applicationState != .background }
        #else
        return true
        #endif
    }

    func start() async {
        guard !policy.isEmpty else { return }
        #if canImport(UIKit) && !os(watchOS)
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: nil
        ) { _ in
            Task { await BuzzKit.instanceIfConfigured?.notificationClearer.appOpened() }
        }
        #endif
        guard await isInForeground() else { return }
        await appOpened()
    }

    func appOpened() async {
        let unthreaded = policy.contains(.unthreaded)
        let threaded = policy.contains(.threads)
        if unthreaded || threaded {
            await clear { notification in
                notification.threadId == nil ? unthreaded : threaded
            }
        }
        if policy.contains(.badge) {
            await store.setBadge(0)
        }
    }

    func notificationOpened(thread: String?) async {
        guard policy.contains(.tappedThread), let thread, !thread.isEmpty else { return }
        await clear(inThread: thread)
        await store.setBadge(await store.active().count)
    }

    func active() async -> [ActiveNotification] {
        await store.active()
    }

    func clearAll() async {
        await clear(where: { _ in true })
    }

    func clear(inThread thread: String) async {
        await clear(where: { $0.threadId == thread })
    }

    func clear(where predicate: @Sendable (ActiveNotification) -> Bool) async {
        let matched = await store.active().filter(predicate).map(\.identifier)
        guard !matched.isEmpty else { return }
        store.remove(identifiers: matched)
        logger.debug("Cleared \(matched.count) delivered notifications")
    }

    func clearBadge() async {
        await store.setBadge(0)
    }
}

#if canImport(UserNotifications)
struct SystemActiveNotificationStore: ActiveNotificationStore {
    func active() async -> [ActiveNotification] {
        await UNUserNotificationCenter.current().deliveredNotifications()
            .compactMap(ActiveNotification.init(notification:))
            .sorted { $0.deliveredAt > $1.deliveredAt }
    }

    func remove(identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func setBadge(_ count: Int) async {
        if #available(iOS 16.0, macCatalyst 16.0, macOS 13.0, *) {
            try? await UNUserNotificationCenter.current().setBadgeCount(count)
        } else {
            #if canImport(UIKit) && !os(watchOS)
            await MainActor.run {
                SystemOpener.sharedApplication?.applicationIconBadgeNumber = count
            }
            #endif
        }
    }
}
#endif
