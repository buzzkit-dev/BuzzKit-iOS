import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

extension BuzzKit {
    /// WidgetKit push updates. Register the widget push token here, then reload widgets
    /// from your server with `buzzkit.widgets.reload({ to })`.
    ///
    /// Works in the app and in the widget extension. In the extension BuzzKit is not
    /// configured, so it reads the API key and the current subscriber from the app group
    /// the app configured with `Configuration.appGroup`.
    public struct Widgets: Sendable {
        let appGroup: String?
        var makeSession: @Sendable () -> URLSession = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            return URLSession(configuration: configuration)
        }

        /// Registers this device's widget push token for the current subscriber. Call it
        /// again whenever the token changes; registration is idempotent.
        public func register(token: Data) async throws {
            let context = try resolveContext()
            let widget = try await context.api.registerWidget(
                RegisterWidgetBody(
                    externalId: context.identity.externalId,
                    identityHash: context.identity.identityHash,
                    token: token.map { String(format: "%02x", $0) }.joined(),
                    environment: context.environment == .sandbox ? "sandbox" : nil
                )
            )
            context.store.set(widget.id, for: StorageKey.widgetId)
        }

        /// Forgets this device's widget registration, so the server stops reloading it.
        public func unregister() async throws {
            let context = try resolveContext()
            guard let id = context.store.string(StorageKey.widgetId) else { return }
            try await context.api.deleteWidget(id: id, identity: context.identity)
            context.store.set(nil as String?, for: StorageKey.widgetId)
        }

        func update(token: Data, installed: Bool) async throws {
            if installed {
                try await register(token: token)
            } else {
                try await unregister()
            }
        }

        private func resolveContext() throws -> WidgetContext {
            if let sdk = BuzzKit.instanceIfConfigured, sdk.configuration.appGroup == appGroup || appGroup == nil {
                let store = KeyValueStore(appGroup: sdk.configuration.appGroup)
                return WidgetContext(
                    api: sdk.api,
                    store: store,
                    identity: try Self.identity(in: store),
                    environment: sdk.configuration.pushEnvironment ?? PushEnvironmentDetector.detect()
                )
            }

            let store = KeyValueStore(appGroup: appGroup)
            guard let apiKey = store.string(SharedConfigurationKey.apiKey),
                let apiURL = store.string(SharedConfigurationKey.apiURL).flatMap(URL.init(string:))
            else {
                throw BuzzKitError.notConfigured
            }
            let http = HTTPClient(
                baseURL: apiURL,
                apiKey: apiKey,
                logger: BKLogger(level: .none),
                session: makeSession(),
                maxAttempts: 2
            )
            return WidgetContext(
                api: ClientAPI(http: http),
                store: store,
                identity: try Self.identity(in: store),
                environment: PushEnvironmentDetector.detect()
            )
        }

        static func identity(in store: KeyValueStore) throws -> SubscriberIdentity {
            if let externalId = store.string(StorageKey.externalId) {
                return SubscriberIdentity(externalId: externalId, identityHash: store.string(StorageKey.identityHash))
            }
            guard let anonymousId = store.string(StorageKey.anonymousId) else { throw BuzzKitError.notConfigured }
            return SubscriberIdentity(externalId: anonymousId, identityHash: nil)
        }
    }

    /// Widget push registration from the app, sharing its configured app group.
    public static var widgets: Widgets {
        Widgets(appGroup: nil)
    }

    /// Widget push registration from the widget extension, through the app group the
    /// app configured BuzzKit with.
    public static func widgets(appGroup: String) -> Widgets {
        Widgets(appGroup: appGroup)
    }
}

#if canImport(WidgetKit) && compiler(>=6.2) && !os(macOS)
@available(iOS 26.0, *)
extension BuzzKit.Widgets {
    /// The body of your `WidgetPushHandler.pushTokenDidChange`: registers the token while
    /// any of your widgets is installed and unregisters when the last one is removed.
    public func pushTokenDidChange(_ pushInfo: WidgetPushInfo, widgets: [WidgetInfo]) async {
        do {
            try await update(token: pushInfo.token, installed: !widgets.isEmpty)
        } catch {
            BKLogger(level: .warn).warn("Widget push registration failed: \(error)")
        }
    }

    /// Registers the current widget push token from the app, for example right after
    /// `identify`, so reloads target the signed-in subscriber.
    public func synchronize() async throws {
        guard let pushInfo = await WidgetCenter.shared.currentPushInfo else { return }
        try await register(token: pushInfo.token)
    }
}
#endif

private struct WidgetContext {
    let api: ClientAPI
    let store: KeyValueStore
    let identity: SubscriberIdentity
    let environment: BuzzKit.PushEnvironment
}
