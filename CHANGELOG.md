# Changelog

## Unreleased

Initial release of the BuzzKit iOS SDK.

- `BuzzKit.configure` with one-line and full-`Configuration` forms
- Anonymous-first identity: stable `anon_` id from first launch, `identify` with
  identity-hash verification, `logout` that detaches the device from the previous user
- `identify(email:)` saves the address on the subscriber and subscribes it once the
  tenant has an email provider; `subscribe: [.email: false]` keeps it on file only
- Durable offline event queue (SQLite): batches of 100 with UUID ids and original
  timestamps, per-identity batching, retry with backoff, flush on launch, foreground,
  identify, and open
- Automatic session events: `$app.opened`, `$app.backgrounded`, `$session.ended`
- `registerForPush`: permission, device token, APNs environment detection from the
  embedded provisioning profile, subscription registration and silent refresh
- App delegate swizzling for token and silent-push callbacks, with manual forwarding
  API and an off switch
- Notification center coordination: configurable foreground presentation,
  `$notification.opened` receipts, forwarding to any pre-existing delegate
- The `bk` payload envelope: message id, deep link, remote action, image, local
  notification plan, cancel plan
- Deep link routing (delegate → closure → system) and the remotely configurable
  action registry
- Workflow-scheduled local notifications: wall-clock triggers, `cancelOn` event
  cancellation on device, cancel pushes
- Preferences: typed data layer over GET/PATCH preferences and the customizable
  `BuzzKitPreferencesView` drop-in screen
- `BuzzKitNotificationServiceExtension`: rich media attachments and
  `$notification.delivered` receipts with app-group spillover recovery
- Attributes on identify and `setAttributes`, merged server-side
- Action buttons on notifications (registered by the extension, receipts carry the
  tapped action and typed text), thread ids, interruption levels, relevance scores
- Live Activities: `monitor`, `enablePushToStart`, low-level token registration, and
  remote start/update/end through the API
- `$app.installed`, `$app.updated`, and `$notification.dismissed` reserved events
- Topic categories: grouped sections in `BuzzKitPreferencesView`, per-channel menus
  for multi-channel topics, `TopicGroup.group` for custom screens
- The device push permission reported as the `$pushPermission` subscriber attribute,
  for segment and workflow branching
- `registerForPush(provisional:)` and the `ForegroundPresentation` option
- Renames: `automaticSessionTracking`, `automaticPushHandling`; identifiers moved to
  `dev.buzzkit`; the example app is `Examples/Basic`
- Connectivity-aware flushing: the queue drains on reconnect (NWPathMonitor), on
  backgrounding, and on launch; deterministic server rejections drop a batch instead
  of blocking the queue
- Swift 6 strict concurrency throughout, no dependencies, privacy manifests in every
  target
- Runnable simulator example app (`Examples/BuzzKitExample`, XcodeGen) with sample
  `.apns` pushes for the local-notification flow
