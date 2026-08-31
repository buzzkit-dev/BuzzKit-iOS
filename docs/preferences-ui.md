# The preferences screen

`GET`/`PATCH` preferences on the client API are a complete notification-settings
backend; the SDK wraps them twice — as data, and as UI.

## The data layer

```swift
let topics = try await BuzzKit.preferences.all()
try await BuzzKit.preferences.set("gym-reminders", enabled: false)
try await BuzzKit.preferences.set("digest", channel: .push, enabled: true)
```

`Topic` carries the slug, name, description, and the resolved preference per channel —
including whether it is the topic's default or the user's explicit choice.

## The drop-in screen

```swift
import BuzzKitUI

NavigationStack {
    BuzzKitPreferencesView()
        .navigationTitle("Notifications")
}
```

Topics with a category render as grouped sections, in the order the server returns
them, so new topics and categories appear without an app update. A topic on one
channel gets a toggle; a topic on several gets a menu with Off and a per-channel
choice, summarized inline ("Push, Email"). The screen loads on appearance, supports
pull-to-refresh, saves optimistically, and reloads on failure.

The view is only the list body: present it in a page, a sheet, or anywhere else, and
give it its own title. `BuzzKit.TopicGroup.group(topics)` exposes the same grouping
for fully custom screens.

## Your own rows

Keep the loading and saving, own the look:

```swift
BuzzKitPreferencesView { topic, isOptedIn in
    HStack {
        Image(systemName: icon(for: topic.slug))
        Toggle(topic.name, isOn: isOptedIn)
    }
}
```

For a fully custom screen (per-channel toggles, grouping, custom layout), build on the
data layer directly — the drop-in view adds nothing you cannot reach.

For previews, tests, or a proxying backend, hand the view its data source:

```swift
BuzzKitPreferencesView(
    load: { try await myBackend.topics() },
    save: { slug, enabled in try await myBackend.set(slug, enabled: enabled) }
)
```

Identify the user before showing the screen: preferences belong to the identified
subscriber, and work even when push permission was denied.
