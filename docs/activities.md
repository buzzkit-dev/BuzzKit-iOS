# Live Activities

BuzzKit starts, updates, and ends Live Activities remotely. The SDK keeps the push
tokens registered; the API does the rest.

## Keep tokens registered

One call at launch per attributes type does everything:

```swift
BuzzKit.activities.observe(MatchAttributes.self)
```

`observe(_:)` watches every activity of the type, current and future, wherever it
was started: tokens stay registered on every rotation, `$activity.started`, `ended`
and `dismissed` land in the event stream, the server row is cleaned up when the
activity goes away, and on iOS 17.2 the push-to-start token registers too.

Starting one from the app is one line as well, instead of `Activity.request`:

```swift
let activity = try BuzzKit.activities.start(
    MatchAttributes(matchId: "m_1"),
    state: .init(score: 0)
)
```

`BuzzKit.activities.end(activity)` ends it everywhere: device, server, and the
event stream. `monitor(_:)`, `register(id:token:attributesType:)` and
`registerPushToStartToken(_:attributesType:)` remain the low-level surface.

## Drive it from your backend or the API

```
POST /v1/live-activities/send
{ "to": "user_42", "event": "update", "activityId": "m_1",
  "contentState": { "score": 3 }, "alert": { "title": "Goal" } }
```

`event` is `start` (targets the push-to-start token by `attributesType`, carries
`attributes`), `update`, or `end`; `staleDate` and `dismissalDate` are ISO timestamps.
The response reports the APNs outcome per registered token.
