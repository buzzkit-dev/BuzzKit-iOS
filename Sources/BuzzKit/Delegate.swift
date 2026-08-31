import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

/// Observes what BuzzKit does with notifications. Every method is optional; closures on
/// ``BuzzKit/onDeepLink(_:)`` and ``ActionRegistry/register(_:handler:)`` are lighter
/// alternatives for single concerns.
public protocol BuzzKitDelegate: AnyObject, Sendable {
    #if canImport(UserNotifications)
    /// Decides how a notification arriving in the foreground is shown. Return `nil` for
    /// the configured default.
    func buzzKit(_ buzzKit: BuzzKit, willPresent payload: PushPayload) -> UNNotificationPresentationOptions?
    #endif

    /// Called when a BuzzKit push is handled without user interaction: a silent push
    /// scheduling or canceling a local notification.
    func buzzKit(_ buzzKit: BuzzKit, didReceive payload: PushPayload)

    /// Called after the user opened a notification, with the tapped action button's
    /// identifier when one was tapped.
    func buzzKit(_ buzzKit: BuzzKit, didOpen payload: PushPayload, actionIdentifier: String?)

    /// Routes a deep link carried by a notification. Return `true` when handled; on
    /// `false` BuzzKit hands the URL to the system.
    func buzzKit(_ buzzKit: BuzzKit, openDeepLink url: URL) -> Bool
}

extension BuzzKitDelegate {
    #if canImport(UserNotifications)
    public func buzzKit(_ buzzKit: BuzzKit, willPresent payload: PushPayload) -> UNNotificationPresentationOptions? {
        nil
    }
    #endif

    public func buzzKit(_ buzzKit: BuzzKit, didReceive payload: PushPayload) {}

    public func buzzKit(_ buzzKit: BuzzKit, didOpen payload: PushPayload, actionIdentifier: String?) {}

    public func buzzKit(_ buzzKit: BuzzKit, openDeepLink url: URL) -> Bool {
        false
    }
}
