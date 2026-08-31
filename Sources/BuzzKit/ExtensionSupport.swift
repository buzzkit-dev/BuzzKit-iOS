import Foundation

/// Support for the notification service extension. Not API; the
/// `BuzzKitNotificationServiceExtension` product is the supported surface.
@_spi(BuzzKitInternal)
public enum BuzzKitExtensionSupport {
    /// Sends a `$notification.delivered` receipt from the extension process, spilling
    /// into the shared app group when the network is not available in time.
    public static func trackDelivered(messageId: String, appGroup: String?) async {
        let shared = KeyValueStore(appGroup: appGroup)
        let externalId = shared.string(StorageKey.externalId) ?? shared.string(StorageKey.anonymousId)
        guard let externalId else { return }
        let identityHash = shared.string(StorageKey.externalId) != nil
            ? shared.string(StorageKey.identityHash)
            : nil
        let entry = Spillover.Entry(
            id: UUID().uuidString.lowercased(),
            externalId: externalId,
            identityHash: identityHash,
            name: EventNames.notificationDelivered,
            data: ["messageId": .string(messageId)],
            timestamp: Date()
        )

        guard let apiKey = shared.string(SharedConfigurationKey.apiKey),
            let apiURL = shared.string(SharedConfigurationKey.apiURL).flatMap(URL.init(string:))
        else {
            if appGroup != nil { Spillover.append(entry, to: shared) }
            return
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let client = HTTPClient(
            baseURL: apiURL,
            apiKey: apiKey,
            logger: BKLogger(level: .none),
            session: URLSession(configuration: configuration),
            maxAttempts: 1
        )
        do {
            _ = try await ClientAPI(http: client).trackEvents(
                TrackEventsBody(
                    externalId: entry.externalId,
                    identityHash: entry.identityHash,
                    source: "ios",
                    events: [EventBody(id: entry.id, name: entry.name, data: entry.data, timestamp: entry.timestamp)]
                )
            )
        } catch {
            if appGroup != nil { Spillover.append(entry, to: shared) }
        }
    }
}
