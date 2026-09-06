import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

/// The BuzzKit SDK. Configure once at launch, then use the static surface everywhere.
///
/// ```swift
/// BuzzKit.configure(apiKey: "bk_pk_…")
/// BuzzKit.identify("user_42")
/// let granted = try await BuzzKit.registerForPush()
/// BuzzKit.track("workout.completed")
/// ```
public final class BuzzKit: @unchecked Sendable {
    private static let instanceState = LockedState<BuzzKit?>(nil)

    let configuration: Configuration
    let logger: BKLogger
    let api: ClientAPI
    let identityStore: IdentityStore
    let eventQueue: EventQueue
    let tracker: EventTracker
    let sessionTracker: SessionTracker
    let pushManager: PushManager
    let deepLinkCenter: DeepLinkCenter
    let localScheduler: LocalScheduler
    let connectivity = ConnectivityMonitor()
    private let delegateState = LockedState<(any BuzzKitDelegate)?>(nil)
    private let identityWork = SerialWorkQueue()
    #if canImport(UserNotifications)
    private var coordinator: NotificationCoordinator?
    #endif

    private init(configuration: Configuration) {
        self.configuration = configuration
        let logger = BKLogger(level: configuration.logLevel)
        self.logger = logger
        let api = ClientAPI(
            http: HTTPClient(baseURL: configuration.apiURL, apiKey: configuration.apiKey, logger: logger)
        )
        self.api = api
        let keyValue = KeyValueStore(appGroup: configuration.appGroup)
        self.identityStore = IdentityStore(store: keyValue)
        let eventStore = Self.makeEventStore(appGroup: configuration.appGroup, logger: logger)
        self.eventQueue = EventQueue(store: eventStore, api: api, logger: logger)
        self.tracker = EventTracker(queue: eventQueue, identity: identityStore, logger: logger)
        let queue = eventQueue
        self.sessionTracker = SessionTracker(tracker: tracker) {
            await queue.flush()
        }
        self.pushManager = PushManager(
            configuration: configuration,
            api: api,
            identity: identityStore,
            store: keyValue,
            tracker: tracker,
            logger: logger
        )
        self.deepLinkCenter = DeepLinkCenter(logger: logger)
        self.localScheduler = LocalScheduler(store: keyValue, logger: logger)
    }

    /// Configures the SDK with just an API key and the default options.
    @discardableResult
    public static func configure(apiKey: String) -> BuzzKit {
        configure(with: Configuration(apiKey: apiKey))
    }

    /// Configures the SDK. Call once, as early as possible in the app's launch.
    @discardableResult
    public static func configure(with configuration: Configuration) -> BuzzKit {
        let (instance, created) = instanceState.withLock { current -> (BuzzKit, Bool) in
            if let current {
                current.logger.warn("BuzzKit.configure called more than once; keeping the first configuration")
                return (current, false)
            }
            let created = BuzzKit(configuration: configuration)
            current = created
            return (created, true)
        }
        if created {
            instance.logger.info("BuzzKit \(SDKInfo.version) configured")
            instance.startAfterConfigure()
        }
        return instance
    }

    /// Whether ``configure(with:)`` has run.
    public static var isConfigured: Bool {
        instanceState.read() != nil
    }

    /// Observes what BuzzKit does with notifications: foreground presentation, opens,
    /// and deep links.
    public static var delegate: (any BuzzKitDelegate)? {
        get { instanceIfConfigured?.delegateValue }
        set { instanceIfConfigured?.delegateState.write(newValue) }
    }

    // MARK: - Identity

    /// Identifies the current user. Call at login, or before showing preferences.
    ///
    /// Until this is called the user is tracked under a stable anonymous id; identifying
    /// re-registers the push subscription under the real id and keeps every queued event.
    ///
    /// `email` is saved on the subscriber (it is the same as `attributes["email"]`) and,
    /// once the tenant has an email provider connected, is subscribed as well. Pass
    /// `subscribe: [.email: false]` to keep the address on file without subscribing it.
    public static func identify(
        _ externalId: String,
        email: String? = nil,
        identityHash: String? = nil,
        attributes: [String: JSONValue]? = nil,
        subscribe: [Channel: Bool] = [:]
    ) {
        guard let instance = requireInstance() else { return }
        instance.enqueueIdentityWork {
            await instance.performIdentify(
                externalId: externalId,
                email: email,
                identityHash: identityHash,
                attributes: attributes,
                subscribe: subscribe
            )
        }
    }

    /// Sets custom attributes on the current user, merged with what is already there.
    /// Attributes drive segments and workflow conditions; no backend call needed.
    public static func setAttributes(_ attributes: [String: JSONValue]) {
        guard let instance = requireInstance() else { return }
        instance.enqueueIdentityWork {
            let identity = await instance.identityStore.current
            do {
                _ = try await instance.api.identify(
                    IdentifyBody(
                        externalId: identity.externalId,
                        email: nil,
                        identityHash: identity.identityHash,
                        attributes: attributes
                    )
                )
            } catch {
                instance.logger.warn("Setting attributes failed: \(error)")
            }
        }
    }

    /// Returns the user to a fresh anonymous identity and detaches this device from the
    /// previous user's notifications. Call at sign-out.
    public static func logout() {
        guard let instance = requireInstance() else { return }
        instance.enqueueIdentityWork {
            await instance.performLogout()
        }
    }

    /// The id this device is currently known by: your own id once `identify` has been called,
    /// or the anonymous id the SDK minted before that. Returns nil when BuzzKit is not configured.
    public static func currentExternalId() async -> String? {
        guard let instance = requireInstance() else { return nil }
        return await instance.identityStore.current.externalId
    }

    /// Whether this device is still anonymous, meaning `identify` has not been called since
    /// launch or since the last `logout`.
    public static func isAnonymous() async -> Bool {
        guard let instance = requireInstance() else { return true }
        return await instance.identityStore.current.isAnonymous
    }

    /// Whether an anonymous identity is still waiting to be merged into the identified one,
    /// because the identify call that carried it has not been accepted yet. The SDK resends it
    /// on the next identify and on the next launch until the API settles it.
    public static func hasPendingMerge() async -> Bool {
        guard let instance = requireInstance() else { return false }
        return await instance.identityStore.hasPendingMerge
    }

    // MARK: - Events

    /// Tracks a custom event. Events are queued durably on the device and delivered in
    /// batches, so tracking works offline.
    public static func track(_ name: String, data: [String: JSONValue]? = nil) {
        guard let instance = requireInstance() else { return }
        Task {
            await instance.tracker.track(name, data: data)
            #if canImport(UserNotifications)
            await instance.localScheduler.eventTracked(name)
            #endif
        }
    }

    /// How many tracked events are queued on the device, waiting to be sent.
    public static func pendingEventCount() async -> Int {
        guard let instance = instanceIfConfigured else { return 0 }
        return await instance.eventQueue.pendingCount()
    }

    /// Sends every queued event now instead of waiting for the next automatic flush.
    public static func flushEvents() async {
        guard let instance = requireInstance() else { return }
        await instance.eventQueue.flush()
    }

    // MARK: - Push

    #if canImport(UserNotifications)
    /// Asks for notification permission, obtains the device token, and registers the
    /// push subscription. Returns whether permission was granted; the subscription is
    /// registered either way so silent pushes and permission recovery keep working.
    ///
    /// Pass `provisional: true` to skip the permission prompt entirely: notifications
    /// deliver quietly to Notification Center until the user upgrades or turns them off
    /// from a delivered notification.
    @discardableResult
    public static func registerForPush(provisional: Bool = false) async throws -> Bool {
        guard let instance = requireInstance() else { throw BuzzKitError.notConfigured }
        return try await instance.pushManager.registerForPush(provisional: provisional)
    }

    /// The current notification permission.
    public static func notificationPermission() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }
    #endif

    /// Forwards the APNs device token when app delegate swizzling is disabled.
    public static func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard let instance = instanceIfConfigured else { return }
        Task { await instance.pushManager.handleDeviceToken(deviceToken) }
    }

    /// Forwards the APNs registration failure when app delegate swizzling is disabled.
    public static func didFailToRegisterForRemoteNotifications(error: Error) {
        guard let instance = instanceIfConfigured else { return }
        Task { await instance.pushManager.handleRegistrationFailure(error) }
    }

    /// Handles a remote notification when app delegate swizzling is disabled. Schedules
    /// or cancels local notifications carried by silent pushes.
    public static func didReceiveRemoteNotification(userInfo: [AnyHashable: Any]) async -> BackgroundFetchOutcome {
        await handleRemotePayload(PushPayload(userInfo: userInfo))
    }

    static func handleRemotePayload(_ payload: PushPayload?) async -> BackgroundFetchOutcome {
        guard let instance = instanceIfConfigured, let payload else { return .noData }
        return await instance.handleSilentPush(payload)
    }

    // MARK: - Deep links and actions

    /// Handles every deep link carried by a notification. Lighter alternative to the
    /// delegate; the delegate wins when both are set.
    public static func onDeepLink(_ handler: @escaping @Sendable (URL) -> Void) {
        requireInstance()?.deepLinkCenter.setDeepLinkHandler(handler)
    }

    /// The registry of remotely configured action handlers.
    public static var actions: ActionRegistry {
        guard let instance = requireInstance() else { return ActionRegistry() }
        return instance.deepLinkCenter.actions
    }

    // MARK: - Internal

    var delegateValue: (any BuzzKitDelegate)? {
        delegateState.read()
    }

    private func startAfterConfigure() {
        #if canImport(UserNotifications)
        let coordinator = NotificationCoordinator(sdk: self)
        self.coordinator = coordinator
        coordinator.install()
        #endif
        if configuration.appGroup != nil {
            let shared = KeyValueStore(appGroup: configuration.appGroup)
            shared.set(configuration.apiKey, for: SharedConfigurationKey.apiKey)
            shared.set(configuration.apiURL.absoluteString, for: SharedConfigurationKey.apiURL)
        }
        connectivity.start { [weak self] in
            guard let self else { return }
            Task { await self.eventQueue.flush() }
        }
        Task {
            await retryPendingMerge()
            await trackInstallation()
            if configuration.automaticSessionTracking {
                await sessionTracker.start()
            }
            await drainSpillover()
            #if canImport(UserNotifications)
            await pushManager.synchronizeOnLaunch()
            #endif
            await eventQueue.scheduleFlush(after: 5)
        }
    }

    func trackInstallation() async {
        let store = KeyValueStore(appGroup: configuration.appGroup)
        if store.string(StorageKey.installedAt) == nil {
            store.set(ISO8601.string(from: Date()), for: StorageKey.installedAt)
        }
        let previous: AppRelease? = store.string("appVersionSeen") != nil || store.string("appBuildSeen") != nil
            ? AppRelease(version: store.string("appVersionSeen"), build: store.string("appBuildSeen"))
            : nil
        let current = AppRelease.current()
        if let event = InstallationTracker.event(previous: previous, current: current) {
            await tracker.trackSystem(event.name, data: event.data, timestamp: event.timestamp)
        }
        store.set(current.version, for: "appVersionSeen")
        store.set(current.build, for: "appBuildSeen")
    }

    func drainSpillover() async {
        guard configuration.appGroup != nil else { return }
        let shared = KeyValueStore(appGroup: configuration.appGroup)
        let entries = Spillover.drain(from: shared)
        guard !entries.isEmpty else { return }
        for entry in entries {
            await eventQueue.enqueue(entry.queued)
        }
        logger.info("Recovered \(entries.count) receipts from the notification extension")
    }

    func currentIdentitySnapshot() -> SubscriberIdentity {
        let store = KeyValueStore(appGroup: configuration.appGroup)
        let externalId = store.string(StorageKey.externalId) ?? store.string(StorageKey.anonymousId) ?? "anonymous"
        let hash = store.string(StorageKey.externalId) != nil ? store.string(StorageKey.identityHash) : nil
        return SubscriberIdentity(externalId: externalId, identityHash: hash)
    }

    func enqueueIdentityWork(_ work: @escaping @Sendable () async -> Void) {
        identityWork.enqueue(work)
    }

    func performIdentify(
        externalId: String,
        email: String?,
        identityHash: String?,
        attributes: [String: JSONValue]? = nil,
        subscribe: [Channel: Bool] = [:]
    ) async {
        let (identity, changed, mergedFrom) = await identityStore.identify(
            externalId: externalId,
            identityHash: identityHash
        )
        let subscribeByChannel = Dictionary(uniqueKeysWithValues: subscribe.map { ($0.key.rawValue, $0.value) })
        var failure: Error?

        do {
            _ = try await api.identify(
                IdentifyBody(
                    externalId: identity.externalId,
                    email: email,
                    identityHash: identity.identityHash,
                    attributes: attributes,
                    subscribe: subscribeByChannel.isEmpty ? nil : subscribeByChannel,
                    device: DeviceContext.current(store: KeyValueStore(appGroup: configuration.appGroup)),
                    anonymousId: mergedFrom
                )
            )
        } catch {
            failure = error
            logger.warn("Identify failed, will rely on the next registration: \(error)")
        }
        
        if mergedFrom != nil, resolveMerge(after: failure) == .settle {
            await identityStore.settleMerge()
        }

        if changed {
            await eventQueue.flush()
            await pushManager.reregister()
        }
    }

    private func retryPendingMerge() async {
        guard await identityStore.hasPendingMerge else { return }
        let identity = await identityStore.current
        guard !identity.isAnonymous else { return }
        await performIdentify(externalId: identity.externalId, email: nil, identityHash: identity.identityHash)
    }

    func performLogout() async {
        await pushManager.unregisterCurrentSubscription()
        _ = await identityStore.logout()
        await pushManager.reregister()
        logger.info("Logged out to a fresh anonymous identity")
    }

    func handleNotificationOpen(payload: PushPayload, actionIdentifier: String?, input: String? = nil) {
        Task {
            var data: [String: JSONValue] = [:]
            if let messageId = payload.messageId { data["messageId"] = .string(messageId) }
            if let actionIdentifier { data["action"] = .string(actionIdentifier) }
            if let input { data["input"] = .string(input) }
            if let deepLink = payload.deepLink { data["deepLink"] = .string(deepLink.absoluteString) }
            await tracker.trackSystem(EventNames.notificationOpened, data: data.isEmpty ? nil : data)
            await eventQueue.flush()
        }
        delegateValue?.buzzKit(self, didOpen: payload, actionIdentifier: actionIdentifier)
        deepLinkCenter.dispatch(payload: payload, from: self)
    }

    func handleNotificationDismiss(payload: PushPayload) {
        Task {
            let data: [String: JSONValue]? = payload.messageId.map { ["messageId": .string($0)] }
            await tracker.trackSystem(EventNames.notificationDismissed, data: data)
            await eventQueue.flush()
        }
    }

    func handleSilentPush(_ payload: PushPayload) async -> BackgroundFetchOutcome {
        delegateValue?.buzzKit(self, didReceive: payload)
        #if canImport(UserNotifications)
        if let plan = payload.localPlan {
            await localScheduler.schedule(plan, messageId: payload.messageId)
            var data: [String: JSONValue] = ["localId": .string(plan.id)]
            if let messageId = payload.messageId {
                data["messageId"] = .string(messageId)
            }
            await tracker.trackSystem(EventNames.localScheduled, data: data)
            await eventQueue.flush()
            return .newData
        }
        if let cancel = payload.cancelPlan {
            await localScheduler.cancel(id: cancel.id)
            return .newData
        }
        #endif
        return .noData
    }

    static var instanceIfConfigured: BuzzKit? {
        instanceState.read()
    }

    @discardableResult
    static func requireInstance() -> BuzzKit? {
        let instance = instanceState.read()
        if instance == nil {
            BKLogger(level: .error).error("BuzzKit is not configured; call BuzzKit.configure(apiKey:) first")
        }
        return instance
    }

    /// Feeds a received payload through the same path a notification tap takes, so a
    /// harness can exercise open, action and dismiss handling without driving
    /// SpringBoard. Not API.
    @_spi(BuzzKitInternal)
    public static func openNotification(payload: PushPayload, actionIdentifier: String? = nil, input: String? = nil) {
        requireInstance()?.handleNotificationOpen(payload: payload, actionIdentifier: actionIdentifier, input: input)
    }

    @_spi(BuzzKitInternal)
    public static func dismissNotification(payload: PushPayload) {
        requireInstance()?.handleNotificationDismiss(payload: payload)
    }

    static func resetForTesting() {
        instanceState.write(nil)
    }

    private static func makeEventStore(appGroup: String?, logger: BKLogger) -> SQLiteStore? {
        do {
            let url = try StorePaths.databaseURL(named: "events.sqlite", appGroup: appGroup)
            return try SQLiteStore(path: url.path)
        } catch {
            logger.error("Falling back to in-memory event storage: \(error)")
            return try? SQLiteStore(path: ":memory:")
        }
    }
}

/// The result of handling a silent push, mirrored to `UIBackgroundFetchResult`.
public enum BackgroundFetchOutcome: Sendable {
    case newData
    case noData
}

#if canImport(UIKit) && !os(watchOS)
extension BackgroundFetchOutcome {
    var fetchResult: UIBackgroundFetchResult {
        switch self {
        case .newData: return .newData
        case .noData: return .noData
        }
    }
}
#endif
