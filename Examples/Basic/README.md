# Basic

The runnable demo app: connect with a client key, identify with attributes, register
for push, track events, and browse six presentations of the preferences screen.

## Run it

```sh
open Examples/Basic/Basic.xcodeproj
```

The project is checked in; `xcodegen` is only needed after changing `project.yml`.
Run the `Basic` scheme on any iPhone simulator.

The **Preferences interface** section works immediately, no key needed: the drop-in
screen, in a sheet, brand tinted, plain list, custom rows, and a fully custom screen,
all on demo topics.

To go live, start the API (`bun dev` in the monorepo), create a **client key** in the
dashboard, and paste it into the Connection section. Connect, identify, track: the
subscriber and events appear in the dashboard, and "Notification settings" renders
your real topics with their categories.

## Simulate pushes

```sh
xcrun simctl push booted push-samples/message.apns   # rich push: image, deep link, action
```

Or drag the `.apns` file onto the simulator window.

`local.apns` and `cancel.apns` are the silent pushes the server sends to schedule and
cancel a local notification. A simulator cannot receive those: SpringBoard only supports
content-available pushes on a device, and `simctl push` refuses a payload with no visible
content. Feed them to the SDK directly instead, which is exactly what the app delegate
does for a real silent push:

```swift
let userInfo = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [AnyHashable: Any]
await BuzzKit.didReceiveRemoteNotification(userInfo: userInfo)
```

After `local.apns`, tapping "Track workout.completed" in the app cancels the pending
reminder on the device, no network involved.

Launching with `-preview-preferences [variant]` opens a preferences demo directly
(`grouped`, `sheet`, `tinted`, `plain`, `custom-rows`, `custom-screen`), which is how
the docs screenshots are made.

## The notification service extension

`Extension/NotificationService.swift` is the complete extension for a real app
(rich media, action buttons, delivered receipts). It is not part of the demo target:
extensions need signing and an app group, which the simulator demo keeps out of the
way.
