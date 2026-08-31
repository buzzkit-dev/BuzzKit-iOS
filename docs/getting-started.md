# Getting started

## 1. Get a client key

In the dashboard, create a **client key** (`bk_pk_…`) on the API keys page. Client keys
are embed-safe: they can only identify users, register devices, track events, and read
or update the user's own preferences.

## 2. Add the package

Add `https://github.com/buzzkit/buzzkit-ios` in Xcode and link the `BuzzKit` product to
your app target. Add `BuzzKitUI` if you want the drop-in preferences screen.

## 3. Configure at launch

```swift
import BuzzKit

@main
struct GymApp: App {
    init() {
        BuzzKit.configure(apiKey: "bk_pk_…")
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`BuzzKit.Configuration` holds the options:

| Option | Default | What it does |
| --- | --- | --- |
| `apiURL` | BuzzKit Cloud | The API origin; point it at your own deployment when self-hosting |
| `logLevel` | `.warn` | How much the SDK writes to the system log |
| `foregroundPresentation` | `.banner` | How foreground pushes present (`.banner` or `.hidden`) |
| `automaticSessionTracking` | `true` | Automatic `$app.opened` / `$session.ended` events |
| `appGroup` | `nil` | Shared with the notification service extension for receipts |
| `pushEnvironment` | detected | Force `sandbox` or `production` |
| `automaticPushHandling` | `true` | Hooks the app delegate's push callbacks |

## 4. Xcode capabilities

Swift packages cannot add capabilities or Info.plist keys to your app, so these are
one-time settings on the app target:

| Setting | Needed for |
| --- | --- |
| Push Notifications capability | Everything |
| Background Modes: Remote notifications | Silent pushes and local notification scheduling |
| `NSSupportsLiveActivities` in Info.plist | Live Activities |
| An App Group (app + extension) | Delivered receipts that survive the extension |
| A Notification Service Extension target | Rich media and delivered receipts |

## 5. Identify at login

```swift
BuzzKit.identify("user_42", email: user.email, identityHash: session.buzzkitHash)
```

Call it whenever your user logs in, and `BuzzKit.logout()` when they sign out. Before
login the user is tracked under a stable anonymous id; identify carries their history
over. The `identityHash` is optional in development and strongly recommended in
production — see [identity.md](identity.md).

## 6. Register for push

```swift
let granted = try await BuzzKit.registerForPush()
```

Call it where asking for permission makes sense (onboarding, or right before the first
thing worth notifying about). Registration also runs silently on later launches to keep
the token fresh.

## 7. Send a message

Create a message in the dashboard targeting yourself and press send. From here:

- [push.md](push.md) — presentation, delegate, manual delegate forwarding
- [deep-links.md](deep-links.md) — deep links and remote actions
- [preferences-ui.md](preferences-ui.md) — the settings screen
- [receipts.md](receipts.md) — delivery and open tracking
- [local-notifications.md](local-notifications.md) — workflow-scheduled local delivery
- [identity.md](identity.md) — identity verification
