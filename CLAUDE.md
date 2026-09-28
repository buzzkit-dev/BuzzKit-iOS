# BuzzKit for iOS

The iOS SDK of [buzzkit](../buzzkit): push registration, notification handling and clearing, identity, events, Live Activities, widget push updates and preferences. Swift 6, iOS 15+, Swift Package Manager (`Package.swift`).

## Commands

```sh
swift test                                                          # unit tests (macOS host)
xcodebuild -scheme BuzzKit -destination "generic/platform=iOS" build # the iOS build, including UIKit/WidgetKit-only code
```

Run both: `swift test` compiles for macOS and skips everything behind `canImport(UIKit)` / `canImport(WidgetKit)`.

## Rules

- **Tests ship with the change.** New public API gets tests through `MockAPI` / `MockURLProtocol` (`Tests/BuzzKitTests/TestSupport.swift`); code that talks to the network from an extension takes an injectable session so it can be tested end to end.
- **Docs ship in the same change, on every surface, or it is not done:** `docs/*.md` (one page per feature), `README.md` (the feature tour), `CHANGELOG.md` (`## Unreleased`), and in the buzzkit repo the docs site page (`apps/docs/sdks/ios/*.mdx`, `docs.json` navigation) and the agent skill reference (`apps/marketing/public/.well-known/agent-skills/buzzkit/references/ios-sdk.md`). The public doc comments are part of the docs.
- Extensions (notification service, widget) are not configured BuzzKit processes: they read the API key, API URL and subscriber from the app group the app configured (`Configuration.appGroup`).
