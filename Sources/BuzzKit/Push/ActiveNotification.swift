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
    /// What the SDK clears on its own.
    public struct NotificationClearing: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// When the user taps a notification sent with a `threadId`, removes the rest of
        /// that thread and sets the badge to the number of BuzzKit notifications left.
        /// Every other thread, and every notification without a thread, stays.
        public static let tappedThread = NotificationClearing(rawValue: 1 << 3)
        /// When the app opens, resets the badge to zero.
        public static let badge = NotificationClearing(rawValue: 1 << 0)
        /// When the app opens, removes the BuzzKit notifications sent without a `threadId`.
        public static let unthreaded = NotificationClearing(rawValue: 1 << 1)
        /// When the app opens, removes the BuzzKit notifications of every thread.
        public static let threads = NotificationClearing(rawValue: 1 << 2)
        /// The default: a thread is cleared when one of its notifications is tapped, the
        /// way Messages reads one conversation at a time. Opening the app clears nothing.
        public static let `default`: NotificationClearing = [.tappedThread]
        /// Everything: the tapped thread, and the badge and every notification when the
        /// app opens.
        public static let all: NotificationClearing = [
            .tappedThread, .badge, .unthreaded, .threads,
        ]
    }
}
