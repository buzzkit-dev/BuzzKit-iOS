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

## Clearing notifications and the badge

Tapping a notification reads its conversation. By default, when the user taps a
notification sent with a `threadId`, the rest of that thread leaves Notification Center
and the badge becomes the number of BuzzKit notifications still showing; other threads
and notifications without a thread stay (iOS removes the tapped one itself). Opening the
app on its own clears nothing, the way Messages behaves. iOS never lets an app touch
another app's notifications, and the SDK only removes the ones it delivered, so the
app's own local notifications stay.

`automaticClearing` is an option set:

| Option | When | Clears |
| --- | --- | --- |
| `.tappedThread` | A threaded notification is tapped | The rest of that thread, then the badge counts what is left |
| `.badge` | The app opens | The badge |
| `.unthreaded` | The app opens | Notifications sent without a `threadId` |
| `.threads` | The app opens | Every thread's notifications |

`.default` is `[.tappedThread]`, `.all` is all four, `[]` turns it off. Nothing is cleared
when iOS launches the app in the background; the app-open options run once the user opens
it.

```swift
await BuzzKit.clearNotifications()
await BuzzKit.clearNotifications(inThread: "room:12")
await BuzzKit.clearNotifications { $0.payload.data["orderId"] == .string("o_1") }
await BuzzKit.clearBadge()
let showing = await BuzzKit.activeNotifications()
```

`clearNotifications()` removes everything and resets the badge. The thread and predicate
forms remove only what they match and leave the badge alone, since only the app knows
what the remaining count should be. `activeNotifications()` lists what is still
showing, newest first, with title, body, thread and the parsed `PushPayload`.

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
