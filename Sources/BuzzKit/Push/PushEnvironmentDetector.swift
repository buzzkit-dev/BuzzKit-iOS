import Foundation

enum PushEnvironmentDetector {
    static func detect(bundle: Bundle = .main) -> BuzzKit.PushEnvironment {
        #if targetEnvironment(simulator)
        return .sandbox
        #else
        if let profile = embeddedProfile(in: bundle), let environment = apsEnvironment(in: profile) {
            return environment == "development" ? .sandbox : .production
        }
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
        #endif
    }

    static func embeddedProfile(in bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return String(data: data, encoding: .isoLatin1)
    }

    static func apsEnvironment(in profile: String) -> String? {
        guard let keyRange = profile.range(of: "<key>aps-environment</key>") else { return nil }
        let after = profile[keyRange.upperBound...]
        guard let open = after.range(of: "<string>"), let close = after.range(of: "</string>"),
            open.upperBound <= close.lowerBound
        else { return nil }
        let value = after[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
