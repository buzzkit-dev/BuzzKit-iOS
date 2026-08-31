# BuzzKit iOS SDK

The native Swift SDK for [BuzzKit](https://buzzkit.dev) — everything an iOS app
needs for push notifications, with no backend code: identify users, track events,
register for push, show a notification-settings screen, handle deep links, run remotely
configured actions, and deliver offline-safe local notifications scheduled by workflows.

```swift
import BuzzKit

BuzzKit.configure(apiKey: "bk_pk_…")
BuzzKit.identify("user_42")
let granted = try await BuzzKit.registerForPush()
BuzzKit.track("workout.completed", data: ["duration": 42])
```

That is the whole integration. Messages, segments, workflows, and topics are managed in
the dashboard; the SDK keeps the device, the user, and their preferences in sync.

## Installation

Add the package in Xcode (File → Add Package Dependencies) or in `Package.swift`:

```swift
.package(url: "https://github.com/buzzkit/buzzkit-ios", from: "0.1.0")
```

Three products:

| Product | Add to | What it does |
| --- | --- | --- |
| `BuzzKit` | the app | The SDK: identity, events, push, preferences, deep links |
| `BuzzKitUI` | the app | `BuzzKitPreferencesView`, the drop-in settings screen |
| `BuzzKitNotificationServiceExtension` | a notification service extension target | Rich media and delivered receipts |

## Configure

```swift
@main
struct GymApp: App {
    init() {
        BuzzKit.configure(with: BuzzKit.Configuration(
            apiKey: "bk_pk_…",
            appGroup: "group.com.example.gym"
        ))
    }
    …
}
```

The client key comes from the dashboard's API keys page and is safe to ship in the
binary. Self-hosting? Point `apiURL` at your deployment. The app group is shared with
the notification service extension so delivered receipts survive its short lifetime.

## Identify and track

Users start under a stable anonymous id from first launch; everything tracked before
login carries over.

```swift
BuzzKit.identify("user_42", email: "ada@example.com", identityHash: hash)
BuzzKit.setAttributes(["plan": "pro", "streak": 4])
BuzzKit.track("workout.completed", data: ["duration": 42])
BuzzKit.logout()
```

Events are written to disk before anything touches the network, batched, and retried —
tracking works on the subway. The queue flushes when the app comes back online, when
it goes to the background, and on every launch; a batch is deleted only after the
server acknowledged it. The `identityHash` comes from your backend and proves the
user is who they claim to be; see [docs/identity.md](docs/identity.md).

## Push

```swift
let granted = try await BuzzKit.registerForPush()
```

One call: permission prompt, device token, environment detection (sandbox in debug
builds and simulators, production in release), and subscription registration. The SDK
hooks the app delegate's token callbacks for you; set
`Configuration.automaticPushHandling` to `false` to forward them yourself. Foreground
notifications show as banners by default — override per notification through
`BuzzKitDelegate`. See [docs/push.md](docs/push.md).

## Deep links and remote actions

A message created in the dashboard can carry a deep link or name an action; the SDK
routes both when the notification is opened.

```swift
BuzzKit.onDeepLink { url in router.open(url) }
BuzzKit.actions.register("show_offer") { action in
    paywall.present(offerId: action.data["offerId"])
}
```

Unhandled deep links fall through to the system. See
[docs/deep-links.md](docs/deep-links.md).

## Preferences

```swift
BuzzKitPreferencesView()                       // the whole settings screen
let topics = try await BuzzKit.preferences.all()   // or build your own UI
try await BuzzKit.preferences.set("gym-reminders", enabled: false)
```

The default screen loads the user's topics with a toggle each; pass a row builder to
own the look completely. See [docs/preferences-ui.md](docs/preferences-ui.md).

## Live Activities

```swift
BuzzKit.activities.monitor(activity)                     // keeps tokens registered
BuzzKit.activities.enablePushToStart(for: MatchAttributes.self)
```

Start, update, and end Live Activities from the dashboard or the API; the SDK only
does the token plumbing. See [docs/activities.md](docs/activities.md).

## Rich media and receipts

Add a notification service extension target with one line of code:

```swift
final class NotificationService: BuzzKitNotificationService {
    override var buzzKitAppGroup: String? { "group.com.example.gym" }
}
```

Images attach to notifications, and every delivery reports back as a
`$notification.delivered` event — opens report as `$notification.opened`. See
[docs/receipts.md](docs/receipts.md).

## Local notifications from workflows

A workflow step with `deliver: "local"` sends a silent push that schedules the
notification on the device, so it fires on time even in airplane mode — and cancels
itself when the user does the thing it was nudging them about. Nothing to implement;
see [docs/local-notifications.md](docs/local-notifications.md).

## Requirements

- iOS 15+ (BuzzKitUI: iOS 15+, Mac Catalyst 15+)
- Swift 6 toolchain (the package builds with strict concurrency)

## Documentation

Start at [docs/getting-started.md](docs/getting-started.md).
