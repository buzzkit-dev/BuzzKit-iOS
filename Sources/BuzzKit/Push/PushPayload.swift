import Foundation

/// A parsed BuzzKit push notification.
public struct PushPayload: Sendable, Equatable {
    /// The message this push delivers, used for delivered and opened receipts.
    public let messageId: String?
    /// The URL to open or route when the notification is tapped.
    public let deepLink: URL?
    /// A remotely configured action to run when the notification is tapped.
    public let action: RemoteAction?
    /// The rich media attachment, downloaded by the notification service extension.
    public let imageURL: URL?
    /// A local notification to schedule instead of showing this push.
    public let localPlan: LocalNotificationPlan?
    /// A request to cancel a previously scheduled local notification.
    public let cancelPlan: CancelPlan?
    /// Action buttons configured on the message, registered by the notification
    /// service extension before display.
    public let actions: [NotificationAction]
    /// The notification category the actions belong to.
    public let categoryId: String?
    /// The custom data attached to the message, exactly as sent.
    public let data: [String: JSONValue]

    /// Parses a notification's `userInfo`. Returns `nil` when the push did not come
    /// from BuzzKit.
    public init?(userInfo: [AnyHashable: Any]) {
        let bk = userInfo["bk"] as? [String: Any] ?? [:]
        let rootMessageId = userInfo["messageId"] as? String
        guard !bk.isEmpty || rootMessageId != nil else { return nil }

        messageId = bk["messageId"] as? String ?? rootMessageId
        let deepLinkString = bk["deepLink"] as? String ?? userInfo["deepLink"] as? String
        deepLink = deepLinkString.flatMap(URL.init(string:))
        action = RemoteAction(raw: bk["action"])
        let image = bk["image"] as? String ?? userInfo["imageUrl"] as? String
        imageURL = image.flatMap(URL.init(string:))
        localPlan = LocalNotificationPlan(raw: bk["local"])
        cancelPlan = CancelPlan(raw: bk["cancel"])
        actions = (bk["actions"] as? [[String: Any]])?.compactMap(NotificationAction.init(raw:)) ?? []
        categoryId = bk["category"] as? String

        var custom: [String: JSONValue] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String else { continue }
            guard !["aps", "bk", "messageId", "imageUrl", "deepLink"].contains(key) else { continue }
            custom[key] = JSONValue(any: value)
        }
        data = custom
    }
}

/// A button on a notification, configured on the message.
public struct NotificationAction: Sendable, Equatable {
    public let id: String
    public let title: String
    public let destructive: Bool
    public let foreground: Bool
    public let input: Bool
    public let placeholder: String?

    init?(raw: [String: Any]) {
        guard let id = raw["id"] as? String, let title = raw["title"] as? String else { return nil }
        self.id = id
        self.title = title
        self.destructive = raw["destructive"] as? Bool ?? false
        self.foreground = raw["foreground"] as? Bool ?? false
        self.input = raw["input"] as? Bool ?? false
        self.placeholder = raw["placeholder"] as? String
    }
}

/// An action configured on the message in the dashboard, run by a handler the app
/// registered with ``BuzzKit/actions``.
public struct RemoteAction: Sendable, Equatable {
    public let name: String
    public let data: [String: JSONValue]

    init?(raw: Any?) {
        guard let raw = raw as? [String: Any], let name = raw["name"] as? String else { return nil }
        self.name = name
        self.data = (raw["data"] as? [String: Any])
            .map { $0.compactMapValues { JSONValue(any: $0) } } ?? [:]
    }
}

/// A local notification carried by a silent push, scheduled on the device so it fires
/// even offline.
public struct LocalNotificationPlan: Sendable, Equatable {
    public let id: String
    public let fireAt: DateComponents
    public let cancelOn: [String]
    public let title: String
    public let body: String
    public let data: [String: JSONValue]

    init?(raw: Any?) {
        guard let raw = raw as? [String: Any],
            let id = raw["id"] as? String,
            let at = raw["at"] as? String,
            let components = Self.wallClockComponents(from: at),
            let title = raw["title"] as? String
        else { return nil }
        self.id = id
        self.fireAt = components
        self.cancelOn = raw["cancelOn"] as? [String] ?? []
        self.title = title
        self.body = raw["body"] as? String ?? ""
        self.data = (raw["data"] as? [String: Any])
            .map { $0.compactMapValues { JSONValue(any: $0) } } ?? [:]
    }

    static func wallClockComponents(from string: String) -> DateComponents? {
        let parts = string.split(separator: "T", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let date = parts[0].split(separator: "-").compactMap { Int($0) }
        let time = parts[1].prefix(8).split(separator: ":").compactMap { Int($0) }
        guard date.count == 3, time.count >= 2 else { return nil }
        var components = DateComponents()
        components.year = date[0]
        components.month = date[1]
        components.day = date[2]
        components.hour = time[0]
        components.minute = time[1]
        components.second = time.count > 2 ? time[2] : 0
        return components
    }
}

/// A request to cancel the scheduled local notification with the same id.
public struct CancelPlan: Sendable, Equatable {
    public let id: String

    init?(raw: Any?) {
        guard let raw = raw as? [String: Any], let id = raw["id"] as? String else { return nil }
        self.id = id
    }
}
