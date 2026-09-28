import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// A BuzzKit notification still showing in Notification Center.
public struct ActiveNotification: Sendable, Equatable {
    public let identifier: String
    public let payload: PushPayload
    public let title: String
    public let subtitle: String
    public let body: String
    public let threadId: String?
    public let deliveredAt: Date

    public init(
        identifier: String,
        payload: PushPayload,
        title: String,
        subtitle: String = "",
        body: String,
        threadId: String?,
        deliveredAt: Date
    ) {
        self.identifier = identifier
        self.payload = payload
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.threadId = threadId
        self.deliveredAt = deliveredAt
    }

    #if canImport(UserNotifications)
    init?(notification: UNNotification) {
        let content = notification.request.content
        guard let payload = PushPayload(userInfo: content.userInfo) else { return nil }
        self.init(
            identifier: notification.request.identifier,
            payload: payload,
            title: content.title,
            subtitle: content.subtitle,
            body: content.body,
            threadId: content.threadIdentifier.isEmpty ? nil : content.threadIdentifier,
            deliveredAt: notification.date
        )
    }
    #endif
}

extension BuzzKit {
    /// What the SDK clears when the app launches or returns to the foreground.
    public struct NotificationClearing: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// When the app opens, resets the app icon badge to zero.
        public static let badge = NotificationClearing(rawValue: 1 << 0)
        /// When the app opens, removes the BuzzKit notifications that were sent without
        /// a `threadId`. Notifications from other sources stay.
        public static let notifications = NotificationClearing(rawValue: 1 << 1)
        /// When the app opens, removes the BuzzKit notifications of every thread as
        /// well, instead of leaving each thread until it is opened.
        public static let threads = NotificationClearing(rawValue: 1 << 2)
        /// When the user opens a notification sent with a `threadId`, removes the rest
        /// of that thread and leaves every other thread alone.
        public static let openedThread = NotificationClearing(rawValue: 1 << 3)
        /// The default: the badge and the unthreaded notifications when the app opens,
        /// and each thread when one of its notifications is opened.
        public static let `default`: NotificationClearing = [.badge, .notifications, .openedThread]
        /// Everything, including every thread when the app opens.
        public static let all: NotificationClearing = [.badge, .notifications, .threads, .openedThread]
    }
}
