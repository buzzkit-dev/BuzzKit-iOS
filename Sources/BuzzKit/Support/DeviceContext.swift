import Foundation
#if canImport(UIKit) && !os(watchOS)
import UIKit
#endif

struct DeviceContext: Encodable, Sendable {
    let appVersion: String?
    let appBuild: String?
    let sdkVersion: String
    let osVersion: String
    let model: String?
    let locale: String
    let installedAt: String?

    static func current(store: KeyValueStore) -> DeviceContext {
        let release = AppRelease.current()
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceContext(
            appVersion: release.version,
            appBuild: release.build,
            sdkVersion: SDKInfo.version,
            osVersion: "\(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : ""),
            model: hardwareModel(),
            locale: Locale.current.identifier,
            installedAt: store.string(StorageKey.installedAt)
        )
    }

    private static func hardwareModel() -> String? {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let identifier = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? nil : identifier
    }
}
