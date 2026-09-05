@_spi(BuzzKitInternal) import BuzzKit
import SwiftUI
import UserNotifications

/// The harness the e2e runner drives. It has no interesting UI: every SDK callback is
/// reported to the runner's collector, which is what the scenarios assert on.
@main
struct E2EApp: App {
    @StateObject private var observer = Observer()

    init() {
        let environment = HarnessSettings.resolve()
        Reporter.run = environment["E2E_RUN"] ?? "unknown"
        Reporter.collector = environment["E2E_COLLECTOR"].flatMap(URL.init(string:))

        guard let key = environment["E2E_API_KEY"], !key.isEmpty,
            let api = environment["E2E_API_URL"].flatMap(URL.init(string:))
        else {
            Reporter.send("configure.skipped")
            return
        }

        BuzzKit.configure(
            with: BuzzKit.Configuration(
                apiKey: key,
                apiURL: api,
                logLevel: .debug,
                appGroup: "group.dev.buzzkit.e2e"
            )
        )
        BuzzKit.onDeepLink { url in
            Reporter.send("deepLink", ["url": url.absoluteString])
        }
        for name in HarnessSettings.resolve()["E2E_ACTIONS"]?.split(separator: ",") ?? [] {
            let action = String(name)
            BuzzKit.actions.register(action) { remote in
                Reporter.send("action", ["name": action, "data": "\(remote.data)"])
            }
        }
        CommandChannel.run = Reporter.run
        CommandChannel.collector = Reporter.collector
        Reporter.send("configure.ok", ["apiURL": api.absoluteString])
    }

    var body: some Scene {
        WindowGroup {
            Text("BuzzKit E2E")
                .task { await observer.start() }
        }
    }
}

@MainActor
final class Observer: ObservableObject, BuzzKitDelegate {
    private var started = false

    func start() async {
        guard !started, BuzzKit.isConfigured else { return }
        started = true
        BuzzKit.delegate = self

        let environment = HarnessSettings.resolve()
        if let subscriber = environment["E2E_SUBSCRIBER"], !subscriber.isEmpty {
            BuzzKit.identify(subscriber)
            Reporter.send("identify", ["externalId": subscriber])
        }

        let provisional = environment["E2E_PROVISIONAL"] != "0"
        do {
            let granted = try await BuzzKit.registerForPush(provisional: provisional)
            Reporter.send("registerForPush", ["granted": granted, "provisional": provisional])
        } catch {
            Reporter.send("registerForPush.failed", ["error": String(describing: error)])
        }

        let status = await BuzzKit.notificationPermission()
        Reporter.send("permission", ["status": status.rawValue])
        CommandChannel.start()
    }

    nonisolated func buzzKit(
        _ buzzKit: BuzzKit,
        willPresent payload: PushPayload
    ) -> UNNotificationPresentationOptions? {
        PayloadStore.remember(payload)
        Reporter.send("willPresent", describe(payload))
        return [.banner, .list]
    }

    nonisolated func buzzKit(_ buzzKit: BuzzKit, didReceive payload: PushPayload) {
        PayloadStore.remember(payload)
        Reporter.send("didReceive", describe(payload))
    }

    nonisolated func buzzKit(_ buzzKit: BuzzKit, didOpen payload: PushPayload, actionIdentifier: String?) {
        var fields = describe(payload)
        fields["actionIdentifier"] = actionIdentifier ?? NSNull()
        Reporter.send("didOpen", fields)
    }

    nonisolated func buzzKit(_ buzzKit: BuzzKit, openDeepLink url: URL) -> Bool {
        let handled = url.host != "handler"
        Reporter.send("openDeepLink", ["url": url.absoluteString, "handled": handled])
        return handled
    }

    nonisolated private func describe(_ payload: PushPayload) -> [String: Any] {
        [
            "messageId": payload.messageId ?? NSNull(),
            "deepLink": payload.deepLink?.absoluteString ?? NSNull(),
            "categoryId": payload.categoryId ?? NSNull(),
            "actions": payload.actions.map(\.id),
            "localPlanId": payload.localPlan?.id ?? NSNull(),
            "localCancelOn": payload.localPlan?.cancelOn ?? [],
            "cancelPlanId": payload.cancelPlan?.id ?? NSNull(),
        ]
    }
}
