@_spi(BuzzKitInternal) import BuzzKit
import Foundation
import UserNotifications

enum NotificationServiceWorker {
    static func process(
        payload: PushPayload,
        content: UNMutableNotificationContent,
        appGroup: String?
    ) async {
        async let receipt: Void = sendDeliveredReceipt(payload: payload, appGroup: appGroup)
        await registerActions(payload: payload, content: content)
        await attachImage(payload: payload, to: content)
        await receipt
    }

    private static func registerActions(payload: PushPayload, content: UNMutableNotificationContent) async {
        guard !payload.actions.isEmpty, let categoryId = payload.categoryId else { return }
        let center = UNUserNotificationCenter.current()
        let existing = await center.notificationCategories()
        content.categoryIdentifier = categoryId
        guard !existing.contains(where: { $0.identifier == categoryId }) else { return }
        let actions = payload.actions.map { action -> UNNotificationAction in
            var options: UNNotificationActionOptions = []
            if action.destructive { options.insert(.destructive) }
            if action.foreground { options.insert(.foreground) }
            if action.input {
                return UNTextInputNotificationAction(
                    identifier: action.id,
                    title: action.title,
                    options: options,
                    textInputButtonTitle: action.title,
                    textInputPlaceholder: action.placeholder ?? ""
                )
            }
            return UNNotificationAction(identifier: action.id, title: action.title, options: options)
        }
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: actions,
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        center.setNotificationCategories(existing.union([category]))
    }

    private static func attachImage(payload: PushPayload, to content: UNMutableNotificationContent) async {
        guard let url = payload.imageURL else { return }
        do {
            let (location, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension.isEmpty ? "png" : url.pathExtension)
            try FileManager.default.moveItem(at: location, to: destination)
            let attachment = try UNNotificationAttachment(identifier: "bk.image", url: destination)
            content.attachments = [attachment]
        } catch {
            return
        }
    }

    private static func sendDeliveredReceipt(payload: PushPayload, appGroup: String?) async {
        guard let messageId = payload.messageId else { return }
        await BuzzKitExtensionSupport.trackDelivered(messageId: messageId, appGroup: appGroup)
    }
}
