import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

actor PushManager {
    private let configuration: BuzzKit.Configuration
    private let api: ClientAPI
    private let identity: IdentityStore
    private let store: KeyValueStore
    private let tracker: EventTracker
    private let logger: BKLogger
    private var tokenContinuations: [CheckedContinuation<String, Error>] = []

    init(
        configuration: BuzzKit.Configuration,
        api: ClientAPI,
        identity: IdentityStore,
        store: KeyValueStore,
        tracker: EventTracker,
        logger: BKLogger
    ) {
        self.configuration = configuration
        self.api = api
        self.identity = identity
        self.store = store
        self.tracker = tracker
        self.logger = logger
    }

    #if canImport(UserNotifications)
    func registerForPush(provisional: Bool = false) async throws -> Bool {
        let center = UNUserNotificationCenter.current()
        var options: UNAuthorizationOptions = [.alert, .badge, .sound]
        if provisional { options.insert(.provisional) }
        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: options)
        } catch {
            throw BuzzKitError.permissionDenied
        }
        await trackPermissionState()
        do {
            let token = try await requestDeviceToken()
            await registerSubscription(token: token)
        } catch {
            logger.warn("Device token registration failed: \(error)")
            if granted { throw BuzzKitError.network(underlying: error) }
        }
        return granted
    }

    func synchronizeOnLaunch() async {
        await trackPermissionState()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            || store.string(StorageKey.deviceToken) != nil
        else { return }
        do {
            let token = try await requestDeviceToken()
            await registerSubscription(token: token)
        } catch {
            logger.debug("Silent token refresh skipped: \(error)")
        }
    }

    func trackPermissionState() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let status = describe(settings.authorizationStatus)
        let previous = store.string(StorageKey.permissionStatus)
        guard previous != status else { return }
        store.set(status, for: StorageKey.permissionStatus)
        if previous != nil || status == "authorized" || status == "denied" {
            await tracker.trackSystem(EventNames.permissionChanged, data: ["status": .string(status)])
        }
        await syncPermissionAttribute(status)
    }

    private func syncPermissionAttribute(_ status: String) async {
        let current = await identity.current
        do {
            _ = try await api.identify(
                IdentifyBody(
                    externalId: current.externalId,
                    email: nil,
                    identityHash: current.identityHash,
                    attributes: nil,
                    pushPermission: status
                )
            )
        } catch {
            logger.debug("Permission attribute sync deferred: \(error)")
        }
    }

    private func describe(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        default: return "notDetermined"
        }
    }
    #endif

    func requestDeviceToken() async throws -> String {
        if let cached = store.string(StorageKey.deviceToken) {
            requestRemoteRegistration()
            return cached
        }
        return try await withCheckedThrowingContinuation { continuation in
            tokenContinuations.append(continuation)
            requestRemoteRegistration()
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await self?.timeOutTokenWait()
            }
        }
    }

    private nonisolated func requestRemoteRegistration() {
        #if canImport(UIKit) && !os(watchOS)
        Task { @MainActor in
            AppDelegateSwizzler.installIfNeeded(swizzles: BuzzKit.instanceIfConfigured?.configuration.automaticPushHandling ?? true)
            SystemOpener.sharedApplication?.registerForRemoteNotifications()
        }
        #endif
    }

    func handleDeviceToken(_ data: Data) async {
        let token = data.map { String(format: "%02x", $0) }.joined()
        let previous = store.string(StorageKey.deviceToken)
        store.set(token, for: StorageKey.deviceToken)
        let continuations = tokenContinuations
        tokenContinuations = []
        for continuation in continuations {
            continuation.resume(returning: token)
        }
        if continuations.isEmpty, previous != token {
            await registerSubscription(token: token)
        }
    }

    func handleRegistrationFailure(_ error: Error) {
        let continuations = tokenContinuations
        tokenContinuations = []
        for continuation in continuations {
            continuation.resume(throwing: error)
        }
        logger.warn("Remote notification registration failed: \(error)")
    }

    private func timeOutTokenWait() {
        guard !tokenContinuations.isEmpty else { return }
        let continuations = tokenContinuations
        tokenContinuations = []
        for continuation in continuations {
            continuation.resume(throwing: BuzzKitError.network(underlying: URLError(.timedOut)))
        }
    }

    func reregister() async {
        guard let token = store.string(StorageKey.deviceToken) else { return }
        await registerSubscription(token: token)
    }

    func unregisterCurrentSubscription() async {
        guard let subscriptionId = store.string(StorageKey.subscriptionId) else { return }
        let current = await identity.current
        do {
            try await api.deleteSubscription(id: subscriptionId, identity: current.subscriberIdentity)
            store.set(nil as String?, for: StorageKey.subscriptionId)
        } catch {
            logger.warn("Failed to remove the push subscription at logout: \(error)")
        }
    }

    private func registerSubscription(token: String) async {
        let current = await identity.current
        let environment = configuration.pushEnvironment ?? PushEnvironmentDetector.detect()
        store.set(environment.rawValue, for: StorageKey.deviceTokenEnvironment)
        do {
            let subscription = try await api.registerSubscription(
                RegisterSubscriptionBody(
                    externalId: current.externalId,
                    channel: "push",
                    platform: "ios",
                    token: token,
                    environment: environment == .sandbox ? "sandbox" : nil,
                    identityHash: current.identityHash,
                    pushPermission: store.string(StorageKey.permissionStatus),
                    device: DeviceContext.current(store: store)
                )
            )
            store.set(subscription.id, for: StorageKey.subscriptionId)
            logger.info("Push subscription \(subscription.id) registered for \(current.externalId)")
        } catch {
            logger.error("Push subscription registration failed: \(error)")
        }
    }
}
