@_spi(BuzzKitInternal) import BuzzKit
import Foundation
import UserNotifications

/// The whole notification service extension. Subclass it, set the subclass as the
/// extension's principal class, and rich media plus delivered receipts work:
///
/// ```swift
/// final class NotificationService: BuzzKitNotificationService {}
/// ```
///
/// Override ``buzzKitAppGroup`` with the app group shared with the main app so
/// receipts survive the extension's short lifetime.
open class BuzzKitNotificationService: UNNotificationServiceExtension, @unchecked Sendable {
    private let pending = BuzzKitLockedState<(
        handler: ((UNNotificationContent) -> Void)?,
        content: UNMutableNotificationContent?
    )>((handler: nil, content: nil))

    /// The app group shared with the main app. Without it receipts are sent best
    /// effort and never recovered after a network failure.
    open var buzzKitAppGroup: String? { nil }

    override open func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        pending.withLock { state in
            state.handler = contentHandler
            state.content = content
        }

        guard let content, let payload = PushPayload(userInfo: request.content.userInfo) else {
            finish()
            return
        }

        let group = buzzKitAppGroup
        let boxedContent = BuzzKitUncheckedSendableBox(content)
        let boxedSelf = BuzzKitUncheckedSendableBox(self)
        Task {
            await NotificationServiceWorker.process(
                payload: payload,
                content: boxedContent.value,
                appGroup: group
            )
            boxedSelf.value.finish()
        }
    }

    override open func serviceExtensionTimeWillExpire() {
        finish()
    }

    private func finish() {
        let (handler, content) = pending.withLock { state -> (((UNNotificationContent) -> Void)?, UNMutableNotificationContent?) in
            let result = (state.handler, state.content)
            state.handler = nil
            return result
        }
        guard let handler, let content else { return }
        handler(content)
    }
}
