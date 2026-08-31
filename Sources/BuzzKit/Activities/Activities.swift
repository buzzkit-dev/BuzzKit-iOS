import Foundation

extension BuzzKit {
    /// Live Activities, remotely driven. `observe(_:)` or `start(_:state:)` do all the
    /// ActivityKit plumbing: token registration, lifecycle events, and server cleanup.
    public struct Activities: Sendable {
        let sdk: BuzzKit?

        /// Registers an activity's push token under its id. Call again on every token
        /// update; registration is idempotent.
        public func register(id: String, token: Data, attributesType: String) async throws {
            try await send(kind: "activity", activityId: id, attributesType: attributesType, token: token)
        }

        /// Registers a push-to-start token, letting the server start an activity of
        /// this attributes type remotely (iOS 17.2 and later).
        public func registerPushToStartToken(_ token: Data, attributesType: String) async throws {
            try await send(kind: "start", activityId: nil, attributesType: attributesType, token: token)
        }

        /// Tells BuzzKit an activity ended locally, so the server stops updating it.
        public func end(id: String) async throws {
            guard let sdk else { throw BuzzKitError.notConfigured }
            let identity = await sdk.identityStore.current
            try await sdk.api.endLiveActivity(id: id, identity: identity.subscriberIdentity)
        }

        func trackLifecycle(_ name: String, id: String, attributesType: String) {
            guard let sdk else { return }
            Task {
                await sdk.tracker.trackSystem(
                    name,
                    data: ["activityId": .string(id), "attributesType": .string(attributesType)]
                )
            }
        }

        private func send(kind: String, activityId: String?, attributesType: String, token: Data) async throws {
            guard let sdk else { throw BuzzKitError.notConfigured }
            let identity = await sdk.identityStore.current
            let environment = sdk.configuration.pushEnvironment ?? PushEnvironmentDetector.detect()
            _ = try await sdk.api.registerLiveActivity(
                RegisterLiveActivityBody(
                    externalId: identity.externalId,
                    identityHash: identity.identityHash,
                    kind: kind,
                    activityId: activityId,
                    attributesType: attributesType,
                    token: token.map { String(format: "%02x", $0) }.joined(),
                    environment: environment == .sandbox ? "sandbox" : nil
                )
            )
        }
    }

    /// Live Activity registration, lifecycle, and observation.
    public static var activities: Activities {
        Activities(sdk: instanceIfConfigured)
    }
}

enum ActivitySeen {
    private static let seen = LockedState<Set<String>>([])

    static func markNew(_ id: String) -> Bool {
        seen.withLock { ids in
            if ids.contains(id) { return false }
            ids.insert(id)
            return true
        }
    }
}
