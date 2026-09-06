import Foundation

final class KeyValueStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private static let prefix = "dev.buzzkit."

    init(appGroup: String? = nil) {
        if let appGroup, let grouped = UserDefaults(suiteName: appGroup) {
            defaults = grouped
        } else {
            defaults = .standard
        }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func string(_ key: String) -> String? {
        defaults.string(forKey: Self.prefix + key)
    }

    func bool(_ key: String) -> Bool? {
        defaults.object(forKey: Self.prefix + key) as? Bool
    }

    func date(_ key: String) -> Date? {
        defaults.object(forKey: Self.prefix + key) as? Date
    }

    func set(_ value: String?, for key: String) {
        write(value, key)
    }

    func set(_ value: Bool?, for key: String) {
        write(value, key)
    }

    func set(_ value: Date?, for key: String) {
        write(value, key)
    }

    private func write(_ value: Any?, _ key: String) {
        if let value {
            defaults.set(value, forKey: Self.prefix + key)
        } else {
            defaults.removeObject(forKey: Self.prefix + key)
        }
    }
}

enum StorageKey {
    static let anonymousId = "anonymousId"
    static let externalId = "externalId"
    static let identityHash = "identityHash"
    static let pendingMergeFrom = "pendingMergeFrom"
    static let email = "email"
    static let subscriptionId = "subscriptionId"
    static let deviceToken = "deviceToken"
    static let deviceTokenEnvironment = "deviceTokenEnvironment"
    static let permissionStatus = "permissionStatus"
    static let installedAt = "installedAt"
}
