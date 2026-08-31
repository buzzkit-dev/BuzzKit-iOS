#if canImport(UserNotifications)
import Foundation
import UserNotifications

final class NotificationCoordinator: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    private unowned let sdk: BuzzKit
    private let forwardee = LockedState<UNUserNotificationCenterDelegate?>(nil)
    private let installed = LockedState(false)

    init(sdk: BuzzKit) {
        self.sdk = sdk
    }

    func install() {
        let firstInstall = installed.withLock { value -> Bool in
            if value { return false }
            value = true
            return true
        }
        guard firstInstall else { return }
        let center = UNUserNotificationCenter.current()
        if let existing = center.delegate, existing !== self {
            forwardee.write(existing)
        }
        center.delegate = self
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let userInfo = notification.request.content.userInfo
        guard let payload = PushPayload(userInfo: userInfo) else {
            if let forwardee = forwardee.read(),
                forwardee.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:withCompletionHandler:))) {
                forwardee.userNotificationCenter?(center, willPresent: notification, withCompletionHandler: completionHandler)
            } else {
                completionHandler([])
            }
            return
        }
        if let choice = sdk.delegateValue?.buzzKit(sdk, willPresent: payload) {
            completionHandler(choice)
        } else if sdk.configuration.foregroundPresentation == .banner {
            completionHandler([.banner, .list, .sound, .badge])
        } else {
            completionHandler([])
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let payload = PushPayload(userInfo: userInfo) else {
            if let forwardee = forwardee.read(),
                forwardee.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
                forwardee.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            } else {
                completionHandler()
            }
            return
        }
        if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            sdk.handleNotificationDismiss(payload: payload)
            if let forwardee = forwardee.read(),
                forwardee.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
                forwardee.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
            } else {
                completionHandler()
            }
            return
        }
        let actionIdentifier = response.actionIdentifier == UNNotificationDefaultActionIdentifier
            ? nil
            : response.actionIdentifier
        let input = (response as? UNTextInputNotificationResponse)?.userText
        sdk.handleNotificationOpen(payload: payload, actionIdentifier: actionIdentifier, input: input)
        if let forwardee = forwardee.read(),
            forwardee.responds(to: #selector(UNUserNotificationCenterDelegate.userNotificationCenter(_:didReceive:withCompletionHandler:))) {
            forwardee.userNotificationCenter?(center, didReceive: response, withCompletionHandler: completionHandler)
        } else {
            completionHandler()
        }
    }
}
#endif
