import Foundation

struct AppRelease: Sendable, Equatable {
    let version: String?
    let build: String?

    static func current(bundle: Bundle = .main) -> AppRelease {
        AppRelease(
            version: bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
            build: bundle.infoDictionary?["CFBundleVersion"] as? String
        )
    }
}

enum InstallationTracker {
    static func event(previous: AppRelease?, current: AppRelease) -> SessionEvent? {
        guard let previous else {
            var data: [String: JSONValue] = [:]
            if let version = current.version { data["version"] = .string(version) }
            if let build = current.build { data["build"] = .string(build) }
            return SessionEvent(name: EventNames.appInstalled, data: data.isEmpty ? nil : data, timestamp: Date())
        }
        guard previous != current else { return nil }
        var data: [String: JSONValue] = [:]
        if let from = previous.version { data["fromVersion"] = .string(from) }
        if let to = current.version { data["toVersion"] = .string(to) }
        if let from = previous.build { data["fromBuild"] = .string(from) }
        if let to = current.build { data["toBuild"] = .string(to) }
        return SessionEvent(name: EventNames.appUpdated, data: data.isEmpty ? nil : data, timestamp: Date())
    }
}
