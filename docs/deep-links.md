# Deep links and remote actions

A message composed in the dashboard can carry a deep link URL, a named action with
data, or both. When the user opens the notification the SDK routes them — this is how
a notification drives the app without an app update.

## Deep links

```swift
BuzzKit.onDeepLink { url in
    router.open(url)
}
```

Resolution order when a notification with a deep link is opened:

1. `BuzzKitDelegate.buzzKit(_:openDeepLink:)` — return `true` to consume the URL.
2. The `onDeepLink` closure.
3. The system (`UIApplication.open`), which handles universal links and other apps'
   schemes.

## Remote actions

Actions are the remotely configurable half: the app registers handlers by name once,
and any message — or workflow step — can invoke them with data chosen in the dashboard.

```swift
BuzzKit.actions.register("show_offer") { action in
    paywall.present(offerId: action.data["offerId"])
}
BuzzKit.actions.register("start_workout") { _ in
    router.open(.workout)
}
```

Ship a handful of capable handlers, then decide in the dashboard which notification
triggers which, with what data. An action with no registered handler logs a warning and
does nothing.

## Opened receipts

Independent of routing, every open is tracked as `$notification.opened` with the
message id — that is what powers open rates and workflow wait-for conditions.
