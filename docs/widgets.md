# Widget push updates

On iOS 26 your server can reload a widget whenever its data changes, without the app
running. BuzzKit keeps the widget's push token registered; your server calls
`buzzkit.widgets.reload({ to })` and WidgetKit reloads the widget's timelines.

A reload is a signal, not data: WidgetKit runs your timeline provider again, which fetches
as it always does. iOS budgets these pushes like timeline reloads and delivers them
opportunistically, so they complement your timeline policy rather than replace it.

## Set up

1. Configure BuzzKit in the app with an app group the widget extension shares:

   ```swift
   BuzzKit.configure(.init(apiKey: "bk_pk_…", appGroup: "group.com.example.app"))
   ```

2. Add the Push Notifications capability to the **widget extension** target.

3. Add a push handler to the widget and hand the token to BuzzKit:

   ```swift
   import BuzzKit
   import WidgetKit

   struct StatsPushHandler: WidgetPushHandler {
       func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) {
           Task {
               await BuzzKit.widgets(appGroup: "group.com.example.app")
                   .pushTokenDidChange(pushInfo, widgets: widgets)
           }
       }
   }

   struct StatsWidget: Widget {
       var body: some WidgetConfiguration {
           AppIntentConfiguration(kind: "Stats", intent: StatsIntent.self, provider: Provider()) { entry in
               StatsView(entry: entry)
           }
           .pushHandler(StatsPushHandler.self)
       }
   }
   ```

`pushTokenDidChange(_:widgets:)` registers the token while any of your widgets is on the
Home Screen and unregisters it when the last one is removed. The extension is not a
configured BuzzKit process: `widgets(appGroup:)` reads the API key and the current
subscriber that the app wrote to the app group.

## Reload from your server

```ts
await buzzkit.widgets.reload({ to: ['user_1', 'user_2'] });
```

Every widget registration of those subscribers gets one push. The call answers a result per
registration; a token APNs reports as invalid is removed.

## After sign-in

A token registered while the device was anonymous follows the person when `identify`
merges the anonymous subscriber. To register it under the signed-in subscriber right away,
call `synchronize()` from the app, which reads the current token from WidgetKit:

```swift
try await BuzzKit.widgets.synchronize()
```

`register(token:)` and `unregister()` remain the low-level surface.
