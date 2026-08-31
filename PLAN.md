# BuzzKit iOS SDK — build plan (E8)

> Status 2026-08-31: steps 1–10 complete. 41 unit tests green (`DEVELOPER_DIR=/Applications/Xcode-27.app/Contents/Developer swift test`), all three products build for the iOS simulator, reviewed (3 findings fixed: silent-push completion merging, serialized identity mutations, generation-guarded preference writes). The server companions below are the remaining buzzkit-repo work.

The native Swift SDK for buzzkit. One package, and the app needs nothing else: identify,
attributes, events, push registration, foreground presentation, receipts, rich media, deep
links, remotely configurable actions, local delivery, and a complete notification-settings
UI — all against `/v1/client/*` with an embeddable `bk_pk_` key.

Quality bar: RevenueCat / Superwall / OneSignal. Native feel: Swift concurrency first,
Sendable-clean under Swift 6 strict concurrency, delegate + closure + async surfaces where
each is idiomatic, no third-party dependencies.

## Package layout

```
Package.swift                     tools 6.0 · iOS 15+ (UI: iOS 16+) · three products
Sources/
  BuzzKit/                        core, no UI
    BuzzKit.swift                 the facade: configure, identify, logout, track, push, …
    Configuration.swift           BuzzKit.Configuration (apiKey, apiURL, options)
    Delegate.swift                BuzzKitDelegate (willPresent, didOpen, deep links)
    Logging/                      Logger over os.Logger, LogLevel
    Networking/                   BuzzKitAPI (endpoints), HTTPClient (URLSession, retry,
                                  Retry-After, exponential backoff), Envelope DTOs
    Storage/                      SQLiteStore (raw sqlite3, no deps), KeyValueStore
    Identity/                     IdentityStore: anonymous id, externalId, identityHash,
                                  aliasing on identify, logout semantics
    Events/                       EventQueue (SQLite offline queue, ≤100/batch, UUID ids,
                                  original timestamps, flush on launch/foreground/timer/
                                  identify), EventTracker (public track + $ events)
    Sessions/                     SessionTracker: $app.opened / $app.backgrounded /
                                  $session.ended(durationSec) from scene lifecycle
    Push/                         PushManager (permission, APNs token, environment
                                  detection, subscription register/refresh),
                                  NotificationCoordinator (UNUserNotificationCenter
                                  delegate with forwarding to the host app's own),
                                  PushPayload (the `bk` envelope parser)
    LocalNotifications/           LocalScheduler: deliver:"local" scheduling with
                                  UNCalendarNotificationTrigger, run tags, cancel pushes,
                                  cancelOnLocal event registry
    Preferences/                  PreferencesClient: fetch + update, models
    DeepLinks/                    DeepLinkCenter: URL routing, remote action registry
  BuzzKitUI/                      BuzzKitPreferencesView (SwiftUI, themable)
  BuzzKitNotificationServiceExtension/
                                  BuzzKitNotificationService: rich media download,
                                  $notification.delivered receipt (direct HTTP within the
                                  NSE budget, app-group spillover queue)
Tests/BuzzKitTests/               unit tests, URLProtocol-mocked network, in-memory SQLite
Examples/BuzzKitExample/          SwiftUI sample app source + walkthrough
docs/                             getting-started, push, deep-links, local-notifications,
                                  preferences-ui, identity, receipts
```

## Public surface (the feel)

```swift
BuzzKit.configure(apiKey: "bk_pk_…")                       // one line; options via Configuration
BuzzKit.identify("user_42", identityHash: hash)             // aliases the anonymous user
BuzzKit.setEmail("ada@example.com")
BuzzKit.track("workout.completed", data: ["duration": 42])
let granted = try await BuzzKit.registerForPush()           // permission + token + register
BuzzKit.logout()

BuzzKit.preferences.all() async throws -> [BuzzKit.Topic]
BuzzKit.preferences.set("gym-reminders", channel: .push, enabled: false)

BuzzKit.onDeepLink { link in … }                            // every push-carried URL
BuzzKit.actions.register("show_offer") { action in … }      // remotely configured actions
BuzzKit.delegate = self                                     // UIKit-style alternative

BuzzKitPreferencesView()                                    // drop-in settings screen
final class NotificationService: BuzzKitNotificationService {}  // the whole NSE
```

## Wire contract (the `bk` envelope)

Pushes carry buzzkit metadata under a single root key so customer `data` stays untouched:

```jsonc
{
  "aps": { … },
  "bk": {
    "messageId": "msg_…",             // receipts: $notification.delivered/opened
    "deepLink": "app://offers/42",    // handed to onDeepLink / openURL fallback
    "action": { "name": "show_offer", "data": { … } },
    "image": "https://…",             // NSE attachment (mutable-content)
    "local": {                        // deliver:"local" (silent push, content-available)
      "id": "run_…:step",             // stable tag for cancellation
      "at": "2026-09-01T19:00:00",    // wall-clock, scheduled in the device zone
      "cancelOn": ["workout.completed"],
      "title": "…", "body": "…", "data": { … }
    },
    "cancel": { "id": "run_…:step" }  // cancel push for a scheduled local notification
  },
  …customer data at root…
}
```

The SDK is the source of truth for this contract. Server companions (small, listed for the
buzzkit repo, to land after the E7 commit):

1. Stamp `bk.messageId` (and `bk.image` instead of root `imageUrl`) in the fan-out payload.
2. Emit the `bk.local` silent push for `deliver: "local"` sends and `bk.cancel` on run
   cancellation (the grammar has carried `deliver` since E5; nothing emits it yet).
3. Accept `attributes` on `POST /v1/client/identify` (no `$` keys, size-capped) so the SDK
   can set attributes without a backend.

Until those land the SDK degrades cleanly: receipts read `bk.messageId ?? messageId` from
the root, images read `bk.image ?? imageUrl`, attributes are queued client-side and sent
once the server accepts them (the call exists in the API surface from day one).

## Behaviors that must be exactly right

- **Offline first**: every event write is durable (SQLite) before any network; batches of
  ≤100 with per-event UUID ids so retries are idempotent server-side; flush on launch,
  foregrounding, timer, identify, and push registration; backoff honors Retry-After.
- **Anonymous → identified**: an anonymous UUID external id from first launch; identify
  re-registers the push subscription under the real id and re-queues nothing (server moves
  the endpoint); logout returns to a fresh anonymous id and clears the identity hash.
- **Foreground presentation**: `showWhileActive` (banner+sound) is the default and the
  delegate can override per-notification; the SDK's center delegate always forwards to any
  delegate the host app had installed first — never steal the center.
- **Receipts**: `$notification.delivered` from the NSE (best effort within its budget,
  spillover into the app group for the next app launch), `$notification.opened` (with
  `action` when a button was tapped) from the app, both carrying `messageId`.
- **Local delivery**: schedule with `UNCalendarNotificationTrigger` in the device zone,
  tag requests with `bk.local.id`, cancel on the cancel push or on any locally tracked
  event named in `cancelOn` — airplane-mode safe by construction.
- **Environment detection**: sandbox vs production APNs from the embedded provisioning
  profile (DEBUG fallback), overridable in Configuration.
- **Privacy**: PrivacyInfo.xcprivacy in every target; no IDFA, no fingerprinting; the only
  identifiers are the ones the host app provides.

## Build loop

1. Plan (this file) → Package.swift, gitignore, license, privacy manifests
2. Core: Configuration, Logger, Envelope models, HTTPClient (+ tests)
3. Storage + Identity (+ tests)
4. EventQueue + EventTracker + SessionTracker (+ tests)
5. PushManager + NotificationCoordinator + PushPayload (+ tests)
6. LocalScheduler + NSE target (+ tests)
7. PreferencesClient + BuzzKitUI view
8. DeepLinkCenter + remote actions (+ tests)
9. README + docs + example app
10. Review: swiftui-expert checklist, API design guidelines pass, `swift test` on host,
    `xcodebuild` against the iOS simulator for all products, iterate to green
