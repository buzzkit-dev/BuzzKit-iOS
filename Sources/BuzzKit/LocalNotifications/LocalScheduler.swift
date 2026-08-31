import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

actor LocalScheduler {
    static let identifierPrefix = "bk.local."

    private let store: KeyValueStore
    private let logger: BKLogger
    private var cancelRegistry: [String: [String]]

    init(store: KeyValueStore, logger: BKLogger) {
        self.store = store
        self.logger = logger
        self.cancelRegistry = Self.loadRegistry(from: store)
    }

    #if canImport(UserNotifications)
    func schedule(_ plan: LocalNotificationPlan, messageId: String?) async {
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        var envelope: [String: Any] = ["local": true, "localId": plan.id]
        if let messageId { envelope["messageId"] = messageId }
        var userInfo: [AnyHashable: Any] = ["bk": envelope]
        for (key, value) in plan.data {
            if let value = value.anyValue { userInfo[key] = value }
        }
        content.userInfo = userInfo

        let trigger = UNCalendarNotificationTrigger(dateMatching: plan.fireAt, repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.identifierPrefix + plan.id,
            content: content,
            trigger: trigger
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            registerCancelEvents(plan.cancelOn, for: plan.id)
            logger.info("Scheduled local notification \(plan.id)")
        } catch {
            logger.error("Failed to schedule local notification \(plan.id): \(error)")
        }
    }

    func cancel(id: String) async {
        let center = UNUserNotificationCenter.current()
        let prefix = Self.identifierPrefix + id
        let pending = await center.pendingNotificationRequests()
        let matched = pending.map(\.identifier).filter { $0 == prefix || $0.hasPrefix(prefix + ":") }
        let identifiers = matched.isEmpty ? [prefix] : matched
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        for identifier in identifiers {
            removeFromRegistry(id: String(identifier.dropFirst(Self.identifierPrefix.count)))
        }
        logger.info("Cancelled \(identifiers.count) local notifications for \(id)")
    }

    func eventTracked(_ name: String) {
        guard let ids = cancelRegistry[name], !ids.isEmpty else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ids.map { Self.identifierPrefix + $0 }
        )
        for id in ids {
            removeFromRegistry(id: id)
        }
        logger.info("Event '\(name)' cancelled \(ids.count) local notifications")
    }
    #endif

    func registerCancelEvents(_ events: [String], for id: String) {
        guard !events.isEmpty else { return }
        for event in events {
            var ids = cancelRegistry[event] ?? []
            if !ids.contains(id) { ids.append(id) }
            cancelRegistry[event] = ids
        }
        persistRegistry()
    }

    func cancelEvents(for id: String) -> [String] {
        cancelRegistry.filter { $0.value.contains(id) }.map(\.key).sorted()
    }

    private func removeFromRegistry(id: String) {
        for (event, ids) in cancelRegistry {
            let remaining = ids.filter { $0 != id }
            cancelRegistry[event] = remaining.isEmpty ? nil : remaining
        }
        persistRegistry()
    }

    private func persistRegistry() {
        let encoded = (try? JSONEncoder().encode(cancelRegistry))
            .map { String(decoding: $0, as: UTF8.self) }
        store.set(encoded, for: "localCancelRegistry")
    }

    private static func loadRegistry(from store: KeyValueStore) -> [String: [String]] {
        guard let raw = store.string("localCancelRegistry"),
            let decoded = try? JSONDecoder().decode([String: [String]].self, from: Data(raw.utf8))
        else { return [:] }
        return decoded
    }
}
