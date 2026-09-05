import Foundation

/// Where the harness reads its `E2E_*` settings from. `simctl launch` passes them as
/// environment variables; a remote simulator that cannot set environment variables
/// gets them written into the built app's Info.plist instead. Environment wins.
enum HarnessSettings {
    static func resolve() -> [String: String] {
        var settings: [String: String] = [:]
        for (key, value) in Bundle.main.infoDictionary ?? [:] where key.hasPrefix("E2E_") {
            if let string = value as? String { settings[key] = string }
        }
        for (key, value) in ProcessInfo.processInfo.environment where key.hasPrefix("E2E_") {
            settings[key] = value
        }
        return settings
    }
}
