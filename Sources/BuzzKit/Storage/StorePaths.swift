import Foundation

enum StorePaths {
    static func databaseURL(named name: String, appGroup: String?) throws -> URL {
        let directory = try baseDirectory(appGroup: appGroup)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory.appendingPathComponent(name)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }

    private static func baseDirectory(appGroup: String?) throws -> URL {
        if let appGroup,
            let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            return container.appendingPathComponent("BuzzKit", isDirectory: true)
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support.appendingPathComponent("BuzzKit", isDirectory: true)
    }
}
