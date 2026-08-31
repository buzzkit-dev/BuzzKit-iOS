# Push

## Registration

```swift
let granted = try await BuzzKit.registerForPush()
```

One call performs the whole flow: the permission prompt, `registerForRemoteNotifications`,
the device token wait, APNs environment detection, and the subscription registration
against the API. It returns whether permission was granted; the token is registered even
when it was not, so silent pushes and permission recovery keep working.

On every later launch the SDK refreshes the token silently when permission was granted
before (or a token was ever obtained), so token rotation never loses a device.

`BuzzKit.notificationPermission()` returns the current `UNAuthorizationStatus`, and
every permission change is tracked as a `$permission.changed` event.

`registerForPush(provisional: true)` skips the permission prompt entirely:
notifications deliver quietly to Notification Center (no banner, no sound) until the
user upgrades from a delivered notification. Quiet delivery without ever asking is
the gentlest onboarding there is; ask properly later, at a moment that earns it.

## Environment

APNs tokens are environment-specific. The SDK reads the embedded provisioning profile:
`aps-environment: development` registers the subscription as `sandbox`, everything else
as production; simulators are always sandbox. Override with
`Configuration.pushEnvironment` when needed.

## Foreground presentation

Notifications arriving while the app is open show as banners with sound by default.
Set `foregroundPresentation: .hidden` globally, or decide per
notification:

```swift
final class Coordinator: BuzzKitDelegate {
    func buzzKit(_ buzzKit: BuzzKit, willPresent payload: PushPayload) -> UNNotificationPresentationOptions? {
        payload.data["priority"] == .string("high") ? [.banner, .sound] : []
    }
}

BuzzKit.delegate = coordinator
```

The SDK installs itself as the notification center delegate and forwards everything to
any delegate your app had installed first — both for its own pushes and for pushes from
other sources, which it never touches.

## Manual delegate forwarding

With `automaticPushHandling: false`, forward the three app delegate callbacks:

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    BuzzKit.didRegisterForRemoteNotifications(deviceToken: deviceToken)
}

func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    BuzzKit.didFailToRegisterForRemoteNotifications(error: error)
}

func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
    await BuzzKit.didReceiveRemoteNotification(userInfo: userInfo).fetchResult
}
```

## The payload

Every BuzzKit push carries its metadata under a single `bk` key, so your own `data`
arrives at the root exactly as sent. `PushPayload(userInfo:)` parses any notification's
`userInfo` into the message id, deep link, action, image, and custom data — it returns
`nil` for pushes that did not come from BuzzKit.

## The full APNs feature set

Everything the message payload supports, end to end:

| Field | What it does |
| --- | --- |
| `title`, `subtitle`, `body` | The alert |
| `imageUrl` | Rich media, attached by the service extension |
| `badge`, `sound` | App badge and sound |
| `actions` | Up to four buttons (`id`, `title`, `destructive`, `foreground`, `input` with `placeholder`); the extension registers the category, taps come back through `didOpen` with the action id, typed text as `input` on the `$notification.opened` receipt |
| `threadId` | Groups notifications in Notification Center |
| `interruptionLevel` | `passive`, `active`, `timeSensitive`, or `critical` |
| `relevanceScore` | 0 to 1, orders the notification summary |
| `category`, `targetContentId`, `collapseId`, `priority` | Passed through to APNs |
| `apns.payload` | The escape hatch, merged into the payload verbatim |

Dismissing an action-bearing notification tracks `$notification.dismissed`.
