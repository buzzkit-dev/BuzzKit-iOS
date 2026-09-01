import Foundation

enum EventNames {
    static let appInstalled = "$app.installed"
    static let appUpdated = "$app.updated"
    static let appOpened = "$app.opened"
    static let appBackgrounded = "$app.backgrounded"
    static let sessionEnded = "$session.ended"
    static let notificationDelivered = "$notification.delivered"
    static let notificationOpened = "$notification.opened"
    static let notificationDismissed = "$notification.dismissed"
    static let localScheduled = "$local.scheduled"
    static let activityStarted = "$activity.started"
    static let activityEnded = "$activity.ended"
    static let activityDismissed = "$activity.dismissed"
    static let activityStale = "$activity.stale"
    static let deeplinkOpened = "$deeplink.opened"
    static let actionTriggered = "$action.triggered"
    static let permissionChanged = "$permission.changed"
    static let identify = "$identify"

    static let reserved: Set<String> = [
        appInstalled, appUpdated,
        appOpened, appBackgrounded, sessionEnded,
        notificationDelivered, notificationOpened, notificationDismissed,
        localScheduled,
        activityStarted, activityEnded, activityDismissed, activityStale,
        deeplinkOpened, actionTriggered,
        permissionChanged, identify,
    ]

    static func isValidCustomName(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("$") && name.utf8.count <= 128
    }
}
