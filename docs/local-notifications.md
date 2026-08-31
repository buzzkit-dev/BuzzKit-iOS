# Local notifications

A workflow step can deliver a message locally: instead of showing a push at send time,
BuzzKit sends a silent push that hands the device a notification to schedule itself.
The device then owns delivery — the notification fires at the right wall-clock time
even with no connectivity, and can cancel itself when the user does the thing it was
about to nudge them for.

Nothing to implement. The SDK:

1. Receives the silent push (`bk.local`) and schedules a `UNCalendarNotificationTrigger`
   notification in the device's timezone.
2. Registers the plan's `cancelOn` event names. When the app tracks a matching event —
   `BuzzKit.track("workout.completed")` — the pending notification is cancelled on the
   device, no network needed.
3. Handles the cancel push (`bk.cancel`) the server sends when a workflow run is
   cancelled centrally. A cancel id matches exactly or as a prefix, so one
   `{ "cancel": { "id": "<runId>" } }` removes every notification that run scheduled.

Silent pushes come with platform limits: iOS budgets them per hour, defers them in
Low Power Mode, and never delivers them to a force-quit app. The schedule is sent when
the workflow's wait begins rather than at fire time, so the carrier has the whole
window to land; an app that stays force-quit for the entire window will not schedule
the notification.

Requirements: the app must have been launched once so the SDK is configured, and
background remote notifications must be enabled (the `remote-notification` background
mode). Scheduled notifications carry the originating message id, so opens are tracked
like any push.
