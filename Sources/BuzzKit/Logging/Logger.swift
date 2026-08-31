import Foundation
import os

/// How much the SDK writes to the system log.
public enum BuzzKitLogLevel: Int, Sendable, Comparable {
    /// Everything, including request and queue internals.
    case debug = 0
    /// Lifecycle milestones: configuration, identification, registration, flushes.
    case info = 1
    /// Recoverable problems the SDK worked around.
    case warn = 2
    /// Failures that dropped work on the floor.
    case error = 3
    /// Nothing.
    case none = 4

    public static func < (lhs: BuzzKitLogLevel, rhs: BuzzKitLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct BKLogger: Sendable {
    let level: BuzzKitLogLevel
    private let logger = os.Logger(subsystem: "dev.buzzkit.sdk", category: "BuzzKit")

    func debug(_ message: @autoclosure () -> String) {
        guard level <= .debug else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }

    func info(_ message: @autoclosure () -> String) {
        guard level <= .info else { return }
        let text = message()
        logger.info("\(text, privacy: .public)")
    }

    func warn(_ message: @autoclosure () -> String) {
        guard level <= .warn else { return }
        let text = message()
        logger.warning("\(text, privacy: .public)")
    }

    func error(_ message: @autoclosure () -> String) {
        guard level <= .error else { return }
        let text = message()
        logger.error("\(text, privacy: .public)")
    }
}
