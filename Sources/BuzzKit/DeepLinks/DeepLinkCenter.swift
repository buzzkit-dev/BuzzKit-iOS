import Foundation

/// Registers handlers for remotely configured actions. A message created in the
/// dashboard can name an action; when the notification is opened the matching handler
/// runs with the action's data.
public struct ActionRegistry: Sendable {
    private let handlers = LockedState<[String: @Sendable (RemoteAction) -> Void]>([:])

    /// Registers the handler for an action name, replacing any previous one.
    public func register(_ name: String, handler: @escaping @Sendable (RemoteAction) -> Void) {
        handlers.withLock { $0[name] = handler }
    }

    /// Removes the handler for an action name.
    public func unregister(_ name: String) {
        handlers.withLock { $0[name] = nil }
    }

    func handler(for name: String) -> (@Sendable (RemoteAction) -> Void)? {
        handlers.withLock { $0[name] }
    }
}

final class DeepLinkCenter: Sendable {
    private let onDeepLink = LockedState<(@Sendable (URL) -> Void)?>(nil)
    let actions = ActionRegistry()
    private let logger: BKLogger

    init(logger: BKLogger) {
        self.logger = logger
    }

    func setDeepLinkHandler(_ handler: (@Sendable (URL) -> Void)?) {
        onDeepLink.write(handler)
    }

    func dispatch(payload: PushPayload, from sdk: BuzzKit) {
        dispatch(
            payload: payload,
            delegateRoute: { url in
                sdk.delegateValue?.buzzKit(sdk, openDeepLink: url) ?? false
            },
            track: { name, data in
                Task { await sdk.tracker.trackSystem(name, data: data) }
            }
        )
    }

    func dispatch(
        payload: PushPayload,
        delegateRoute: (URL) -> Bool,
        track: (String, [String: JSONValue]) -> Void
    ) {
        if let action = payload.action {
            let handler = actions.handler(for: action.name)
            if let handler {
                logger.debug("Running action '\(action.name)'")
                handler(action)
            } else {
                logger.warn("No handler registered for action '\(action.name)'")
            }
            var actionData: [String: JSONValue] = [
                "name": .string(action.name),
                "handled": .bool(handler != nil),
            ]
            actionData.merge(messageData(payload)) { current, _ in current }
            track(EventNames.actionTriggered, actionData)
        }
        guard let url = payload.deepLink else { return }
        let via: String
        if delegateRoute(url) {
            via = "delegate"
        } else if let handler = onDeepLink.read() {
            logger.debug("Routing deep link \(url.absoluteString)")
            handler(url)
            via = "handler"
        } else {
            openWithSystem(url)
            via = "system"
        }
        var linkData: [String: JSONValue] = ["url": .string(url.absoluteString), "via": .string(via)]
        linkData.merge(messageData(payload)) { current, _ in current }
        track(EventNames.deeplinkOpened, linkData)
    }

    private func messageData(_ payload: PushPayload) -> [String: JSONValue] {
        payload.messageId.map { ["messageId": .string($0)] } ?? [:]
    }

    private func openWithSystem(_ url: URL) {
        #if canImport(UIKit) && !os(watchOS)
        Task { @MainActor in
            SystemOpener.open(url)
        }
        #endif
    }
}
