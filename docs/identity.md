# Identity

## Anonymous by default

From first launch the SDK tracks under a stable anonymous id (`anon_…`), persisted on
the device. Events, sessions, and the push subscription all work before anyone logs in.

## Identify

```swift
BuzzKit.identify("user_42", email: user.email, identityHash: hash, attributes: ["plan": "trial"])
BuzzKit.setAttributes(["plan": "pro", "streak": 4])
```

Attributes are custom key-values on the subscriber — they drive segments and workflow
conditions. The device's attributes are merged server-side into what your backend set:
adding and changing keys works from the app alone, and nothing set elsewhere is wiped.

Identify switches the device to the real user: the subscriber is created or updated,
the push subscription is re-registered under the new id, and queued events flush. Call
it at login and on every launch where the user is already logged in (it is idempotent
and cheap).

`BuzzKit.logout()` deletes the device's push subscription for the previous user,
returns to a **fresh** anonymous id, and re-registers the device under it — the next
user of the device never receives the previous user's notifications.

## Identity verification

A client key alone lets any caller claim any external id. In production, prove
identity: your backend computes

```
identityHash = HMAC-SHA256(externalId, identitySecret)   // hex
```

with the tenant's identity secret (fetch it once from the dashboard; never ship it in
the app), and hands the hash to the app at login. Pass it to `identify` and the
subscriber is marked verified; enable **require verification** on the tenant and
unverified calls are rejected entirely.

The SDK carries the hash automatically on every call it makes — events, subscription
updates, preferences — for as long as the user stays identified.

## The push permission attribute

The SDK reports the device's notification permission as the system attribute
`$pushPermission` (`notDetermined`, `denied`, `authorized`, `provisional`,
`ephemeral`), refreshed on launch, registration, and every change. Segments and
workflow branches read it like any attribute — send a push to the authorized, a Live
Activity to the denied.
