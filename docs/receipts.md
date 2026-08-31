# Delivery and open receipts

Every notification reports its lifecycle as events on the subscriber:

| Event | When | Sent by |
| --- | --- | --- |
| `$notification.delivered` | The notification arrived on the device | The service extension |
| `$notification.opened` | The user opened it (with `action` when a button was tapped) | The app |

Both carry the `messageId`, so the dashboard ties them back to the exact send — and
workflows can wait on them.

## Setting up delivered receipts

Delivered receipts need a notification service extension (Apple runs it for every
push with `mutable-content`, which BuzzKit sets on rich pushes):

1. Add a **Notification Service Extension** target in Xcode.
2. Link the `BuzzKitNotificationServiceExtension` product to it.
3. Replace the generated class:

```swift
import BuzzKitNotificationServiceExtension

final class NotificationService: BuzzKitNotificationService {
    override var buzzKitAppGroup: String? { "group.com.example.gym" }
}
```

4. Give the app and the extension the same app group, and pass it in the app's
   `Configuration.appGroup`.

The extension also downloads the notification's image and attaches it.

## The app group

The extension lives for a few seconds. When the receipt cannot be sent in time, it is
written to the shared app group and the app delivers it on the next launch — receipts
are eventually exact, not best effort. Without an app group they are best effort.
